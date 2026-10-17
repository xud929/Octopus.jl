export ThinCrabCavitySpec, ThinCrabCavity

"""
    ThinCrabCavitySpec{N}(frequency; strengthX=(), strengthY=(), phase=(),
                          phase_noise=(), strength_noise=(),
                          tracking_method=Symplectic6DMap(), kwargs...)
    ThinCrabCavitySpec{N,T}(frequency; kwargs...)
    ThinCrabCavitySpec(; frequency, N, kwargs...)

Friendly constructor for `ElementSpec{:thin_crab_cavity}`: a zero-length
two-dimensional crab cavity with `N` harmonics, each carrying a horizontal
strength, a vertical strength, and a phase. `frequency` is in Hz and must be
finite and nonzero. Extra keyword arguments are stored as descriptive spec
metadata. See `element_help(:thin_crab_cavity)` for the parameter schema.

Numeric type: without the explicit `T`, the element type is the promotion of
`frequency`, `strengthX`, `strengthY` and `phase` over a `Float64` FLOOR
(`_linear_map_eltype`, the rule of the linear maps and `Linear6DSpec`), so
integers and `Float32` land on `Float64`, a dual or complex parameter widens
the cavity to its type, and nothing is narrowed -- until 2026-10-16 the type
followed `frequency` alone, so a `Float32` frequency narrowed `Float64`
strengths and phases silently and a complex strength was refused (fix D of
the crab-cavity noise neighbour audit). Narrowing stays behind the explicit
`ThinCrabCavitySpec{N,Float32}` form, which stores and compiles `Float32`: the
one Float32 crab cavity, where a `Float64` `TurnTable` is refused rather than
promoted (the RF twin has no typed form and compiles in `Float64` for every
real parameter precision). A beam whose element type differs from the
cavity's is refused BY NAME when a task compiles the line
(`_required_beam_eltype`, `src/track/Track.jl`): track a `Float32` beam
through `ThinCrabCavitySpec{N,Float32}` and a `Float64` beam through the
untyped form.

`phase_noise` and `strength_noise` declare turn-by-turn modulation, one entry
per harmonic: each entry is `nothing` (inactive, the default for every
harmonic when the keyword is omitted or `()`) or a rule -- `WhiteNoise(sigma;
rng_id)`, `PinkNoise(sigma; rng_id, octaves)`, `TurnTable(offsets; name)` or
`SpectralNoise(sigma, band, spectrum; rng_id, turns)`, which resolves to a
`TurnTable` when the line compiles (`docs/design/spectral_turn_table.md`,
D11) -- whose realised per-turn value is applied once per turn by the
`TurnModulated` wrap that `compile_runtime` builds around the nominal cavity
(`docs/design/turn_modulation.md`). A `phase_noise` value is an offset in rad
added to `phase[i]`; a `strength_noise` value `d` is a dimensionless RELATIVE
factor scaling BOTH planes' strengths of its harmonic, `strengthX[i] (1 + d)`
and `strengthY[i] (1 + d)`: one voltage driver excites a cavity's horizontal
and vertical kick, so one relative amplitude error scales both, and a second
driver is a second cavity (owner decision; relative, 2026-10-15). A plane
whose nominal strength is zero therefore stays exactly zero under amplitude
noise. The nominal values stored here, knob-driven or not, are never changed
by a rule. The whole keyword is a tuple
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
abstract type ThinCrabCavitySpec{N,T} end

# Keyword form: reflection builds every kind by keyword alone (the N harmonic
# count arrives as an ordinary keyword there), and a spec rebuilt from
# `parameter_schema` must round trip (2026-08-05 audit, U3-7).
ThinCrabCavitySpec(; frequency, N, kwargs...) =
    ThinCrabCavitySpec{Int(N)}(frequency; kwargs...)

# Documented on the abstract type above (U6-1): no docstring here on purpose.
# The UNTYPED form: `T` is the promotion of the named numeric parameters over a
# Float64 floor (`_linear_map_eltype`, src/elements/linear_maps.jl; the
# U9-6 rule of the linear maps), never `typeof(float(frequency))` alone, which
# narrowed Float64 strengths to a Float32 frequency (fix D, 2026-10-16). The
# typed method below stores it.
function (::Type{ThinCrabCavitySpec{N}})(frequency::Real;
                                         strengthX=(),
                                         strengthY=(),
                                         phase=(),
                                         kwargs...) where {N}
    T = _linear_map_eltype(frequency, strengthX, strengthY, phase)
    return ThinCrabCavitySpec{N,T}(frequency; strengthX=strengthX, strengthY=strengthY,
                                   phase=phase, kwargs...)
end

# The TYPED form (no docstring here either, U6-1): `T` as given, so
# `ThinCrabCavitySpec{N,Float32}` is the deliberate Float32 cavity, as
# `LumpedRadSpec{Float32}` and `XYCouplingSpec{Float32}` are for their kinds.
function (::Type{ThinCrabCavitySpec{N,T}})(frequency::Real;
                                           strengthX=(),
                                           strengthY=(),
                                           phase=(),
                                           phase_noise=(),
                                           strength_noise=(),
                                           tracking_method=Symplectic6DMap(),
                                           kwargs...) where {N,T}
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
`frequency` must be finite and nonzero. `T` is the promotion of the arguments
over a `Float64` floor in this direct form and the promotion of the stored
parameters' float types when compiled from a spec (`ThinCrabCavitySpec`), so
nothing is narrowed on either route.

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
    T = _linear_map_eltype(frequency, strengthX, strengthY, phase)
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
    strengthX = param(spec, :strengthX)
    strengthY = param(spec, :strengthY)
    phase = param(spec, :phase)
    T = _crab_numeric_type(frequency, strengthX, strengthY, phase)
    _validate_crab_frequency(T(frequency))
    return ThinCrabCavity{N,typeof(method),T}(
        method,
        T(2) * T(pi) * T(frequency) / T(CLIGHT),
        _harmonic_tuple(Val(N), strengthX, T),
        _harmonic_tuple(Val(N), strengthY, T),
        _harmonic_tuple(Val(N), phase, T),
    )
end

# The compiled type is the promotion of the STORED parameters' float types with
# no floor -- `_float_params`' rule for the linear maps -- so the untyped
# friendly form (stored Float64 by its floor) compiles to Float64, the explicit
# `ThinCrabCavitySpec{N,Float32}` to Float32, and a raw
# `ElementSpec{:thin_crab_cavity}` mixing a Float32 frequency with Float64
# strengths to Float64: nothing is narrowed on any route. Until 2026-10-16 this
# was `typeof(float(frequency))`, which narrowed the strengths and phases of a
# Float32-frequency spec and refused a complex or dual strength with an
# `InexactError` (neighbour audit leads U2-1 and S2-3; fix D).
function _crab_numeric_type(frequency, tuples...)
    T = typeof(float(frequency))
    for values in tuples, v in values
        T = promote_type(T, typeof(float(v)))
    end
    return T
end

# A mismatched beam is refused at compile by name (`_required_beam_eltype`,
# src/track/Track.jl; the check in src/tasks/Tasks.jl). This kernel has no
# branch on a runtime flag, so it promotes with the beam on BOTH backends
# (measured 2026-10-16: a Float64 cavity on a Float32 beam runs on the CPU and
# on CUDA, narrowing on store); the refusal here is the owner's consistency
# decision for the two modulated kinds, and `ThinCrabCavitySpec{N,Float32}` is
# the one way to track a Float32 beam through a crab cavity.
_required_beam_eltype(::ThinCrabCavity{N,M,T}) where {N,M,T} = T
_beam_eltype_remedy(::ThinCrabCavity{N,M,T}, ::Type{B}) where {N,M,T,B} =
    "build the cavity in the beam's type, ThinCrabCavitySpec{$(N),$(B)}(frequency; ...), " *
    "or the beam in $(T) (Beam(n, policy, $(T)))"

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
        N=ParamMeta(required=true, meaning="maximum harmonic count encoded by ThinCrabCavitySpec{N} (and by the explicitly typed ThinCrabCavitySpec{N,T})"),
        frequency=ParamMeta(required=true, unit="Hz", meaning="RF frequency"),
        strengthX=ParamMeta(default=(), meaning="horizontal kick strength tuple of length N"),
        strengthY=ParamMeta(default=(), meaning="vertical kick strength tuple of length N"),
        phase=ParamMeta(unit="rad", default=(), meaning="phase tuple of length N"),
        phase_noise=ParamMeta(unit="rad", default=(), meaning="per-harmonic turn-by-turn additive phase modulation, tuple of length N: each entry nothing (inactive) or a rule (WhiteNoise, PinkNoise, TurnTable, SpectralNoise -- the last resolving to a TurnTable at compile_runtime) realised once per turn on the host by the TurnModulated wrap at compile_runtime, never read by the kernel; see src/elements/turn_modulated.jl"),
        strength_noise=ParamMeta(default=(), meaning="per-harmonic turn-by-turn RELATIVE strength modulation, dimensionless, tuple of length N: each entry nothing or a rule whose realised per-turn value d scales BOTH planes' strengths of its harmonic, strengthX[i] (1 + d) and strengthY[i] (1 + d) -- one voltage driver per cavity (relative, 2026-10-15); a WhiteNoise or PinkNoise sigma is the relative rms itself, a TurnTable holds relative factors and a SpectralNoise resolves at compile to such a table"),
        tracking_method=ParamMeta(default=Symplectic6DMap(), meaning="per-element tracking method"),
        _PLACEMENT_PARAMS...,
    )
    example = ThinCrabCavitySpec{2}(1.0e8; strengthX=(1.0, 0.5), strengthY=(0.25, 0.125), phase=(0.0, 0.1))
    construction_help = "Friendly constructor: ThinCrabCavitySpec{N}(frequency; strengthX, strengthY, phase, phase_noise, strength_noise, tracking_method=Symplectic6DMap(), kwargs...), or ThinCrabCavitySpec{N,T}(frequency; ...) with an explicit element type T. Equivalent flexible form: ElementSpec{:thin_crab_cavity}(; N=N, frequency=frequency, strengthX=strengthX, strengthY=strengthY, phase=phase, phase_noise=phase_noise, strength_noise=strength_noise, tracking_method=tracking_method, kwargs...). Harmonic tuples must have length N; omitted tuples are filled with zeros. Numeric type: without T the element type is the promotion of frequency, strengthX, strengthY and phase over a Float64 floor (integers and Float32 land on Float64, a dual or complex parameter widens the cavity, nothing is narrowed); the compiled runtime promotes the stored parameters' types, so ThinCrabCavitySpec{N,Float32} is the deliberate Float32 cavity and the only one; a beam whose element type differs from the cavity's is refused by name when a task compiles the line (build the cavity in the beam's type or the beam in the cavity's). Turn-by-turn modulation: phase_noise and strength_noise are per-harmonic tuples of length N whose entries are nothing (inactive, the default when the keyword is omitted or ()) or a rule, WhiteNoise(sigma; rng_id), PinkNoise(sigma; rng_id, octaves), TurnTable(offsets; name) or SpectralNoise(sigma, band, spectrum; rng_id, turns), which resolves to a TurnTable when the line compiles; the rule's realised per-turn value is applied once per turn by the TurnModulated wrap that compile_runtime builds, never by the kernel: an offset in rad added to the phase for phase_noise; for strength_noise a dimensionless relative factor d scaling both planes of its harmonic, strengthX[i] (1 + d) and strengthY[i] (1 + d) -- one voltage driver per cavity, so a WhiteNoise sigma is the relative rms itself and a TurnTable holds relative factors (relative, 2026-10-15). The whole keyword must be a tuple or vector of N entries or (): a bare nothing (the RF cavity's scalar spelling of inactive) is refused at construction and at compile, not read as all-inactive; a PinkNoise on a cavity with more than 32 harmonics is refused at compile (the pink stride of the counter-RNG keying). Placement (every kind, consumed by the compile-time misalignment and design-roll wraps): x_offset, y_offset, z_offset [m], x_pitch, y_pitch, tilt, ref_tilt [rad], misalign_convention (:bmad or :madx). name: an optional label, carried into beam-line provenance paths and diagnostics, never read by a tracking kernel."
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
entry per harmonic for the phase (`phase_noise`, an offset in rad) and one per
harmonic for the strength (`strength_noise`, a dimensionless relative factor),
each `nothing` (inactive) or a rule (`WhiteNoise`, `PinkNoise`, `TurnTable`; a
`SpectralNoise` has resolved to a `TurnTable` by the time the container is built).
One realised strength factor `d` per harmonic scales BOTH planes' strengths,
`strengthX[i] (1 + d)` and `strengthY[i] (1 + d)`, which is what one cavity
voltage does (relative, 2026-10-15; before, one absolute offset was added to
both planes). Slot numbering handed to `_turn_offset`: harmonic `i`
of the phase is slot `i`, of the strength slot `N + i`, so one `rng_id` shared
by every entry of one cavity still draws independently per entry (a
`SpectralNoise` resolves under the same slot, so its tables are independent
per entry too).
"""
struct CrabCavityNoise{P<:Tuple,S<:Tuple}
    phase::P
    strength::S
end

"""
    _realize_draws(rules::CrabCavityNoise, base::ThinCrabCavity{N,M,T}, ctx) -> (cavity, rules′, draws)
    realize(rules::CrabCavityNoise, base::ThinCrabCavity{N,M,T}, ctx) -> (cavity, rules′)

The cavity to track on turn `ctx.turn`: `base` with each harmonic's realised
phase offset added to `phase[i]` and its realised strength factor `d` scaling
both planes, `strengthX[i] (1 + d)` and `strengthY[i] (1 + d)`, together with
the rules' successors (relative scaling, 2026-10-15; an inactive slot's `d` is
zero and leaves the strengths bitwise unchanged, a zero nominal stays zero)
and, from `_realize_draws`, the `2N` draws in slot order -- the `N` phase
offsets then the `N` strength factors, the very values the cavity above was
built from (`docs/design/turn_modulation_record.md`, D5). `realize` is the
two-element projection.
Phase harmonic `i` is handed slot `i`, strength harmonic `i` slot `N + i`.
The per-slot draws come from `_slot_draws` (`src/elements/turn_modulated.jl`),
unrolled with literal indices so that a MIXED container -- `nothing` beside a
rule, a `PinkNoise` -- is as type-stable as a homogeneous one; the harmonic
tuples are then rebuilt from the homogeneous value tuples with
`ntuple(..., Val(N))` (a `@generated` unroll in Base for every `N`), so the
result has exactly the type of `base`, the successor container the type of
`rules` (every shipped rule is stateless) and the call allocates nothing for
every container shape and harmonic count (the suite pins 0 B on
`(nothing, WhiteNoise)`, `(nothing, PinkNoise)` and a table slot, where the
`ntuple`-over-`rules.phase[i]` form allocated 640 to 736 B per `update`;
review F1, 2026-10-15; and 0 B at 32, 33 and 40 harmonics, where the draws
tuple's `(dphi..., d...)` splat allocated 1.1-2.6 kB per call from 33 on --
`_slot_concat` in `src/elements/turn_modulated.jl` unrolls it with literal
indices; 2026-10-16 neighbour audit, U1-2).
"""
function _realize_draws(rules::CrabCavityNoise, base::ThinCrabCavity{N,M,T},
                        ctx::TrackingContext) where {N,M,T}
    phase_draws = _slot_draws(rules.phase, ctx, 1, T)
    strength_draws = _slot_draws(rules.strength, ctx, N + 1, T)
    dphi = _slot_values(phase_draws)
    d = _slot_values(strength_draws)
    realised = ThinCrabCavity{N,M,T}(
        base.method,
        base.kcc,
        ntuple(a -> base.strengthX[a] * (one(T) + d[a]), Val(N)),
        ntuple(b -> base.strengthY[b] * (one(T) + d[b]), Val(N)),
        ntuple(c -> base.phase[c] + dphi[c], Val(N)),
    )
    successor = CrabCavityNoise(_slot_successors(phase_draws), _slot_successors(strength_draws))
    # `_slot_concat`, not `(dphi..., d...)`: a splat past 32 entries per tuple
    # is a runtime `_apply_iterate` that allocated 1.1-2.6 kB per call from 33
    # harmonics on, on the plain hook too (2026-10-16 neighbour audit, U1-2).
    return realised, successor, _slot_concat(dphi, d)
end

function realize(rules::CrabCavityNoise, base::ThinCrabCavity, ctx::TrackingContext)
    realised, successor, _ = _realize_draws(rules, base, ctx)
    return realised, successor
end

"""
    _turn_modulation_wrap(spec::ElementSpec{:thin_crab_cavity}, inner::ThinCrabCavity)

The crab cavity's method of the compile-time wrap: `inner` itself when every
`phase_noise` and `strength_noise` entry is `nothing`, otherwise
`TurnModulated(inner, CrabCavityNoise(phase_rules, strength_rules))`. Both
parameters pass through `_rule_tuple` here as well, so a raw spec is checked,
and then through `_resolve_turn_rules`, which turns every `SpectralNoise` into
the `TurnTable{T}` it synthesises under the global seed in force, its claimed
`rng_id` and the entry's slot -- phase harmonic `i` is slot `i`, strength
harmonic `i` slot `N + i`, the numbering of `_slot_rules` and of `realize`, so
one `rng_id` on several entries gives independent tables as it gives the live
rules independent draws (review F1, 2026-10-16) -- and the container never
holds the spec-level rule.
A rule bound to a numeric type (`_rule_numeric_type`, a `TurnTable{T′}`) other
than the cavity's `T` is refused with an `ArgumentError` rather than promoted.
`inner` is the NOMINAL cavity: a knob-driven `phase` has already resolved
into it, and the rule's realised value is applied at run time on top of it
(added to the phase, scaling the strengths as `S (1 + d)`).
"""
function _turn_modulation_wrap(spec::ElementSpec{:thin_crab_cavity}, inner::ThinCrabCavity{N,M,T}) where {N,M,T}
    # Resolution (src/elements/turn_modulated.jl, `_resolve_turn_rule`): a
    # `SpectralNoise` entry becomes its `TurnTable{T}` here, under the global
    # seed in force, the rule's claimed rng_id and the entry's slot (phase
    # harmonic i is slot i, strength harmonic i slot N + i); every other
    # entry passes.
    phase_rules = _resolve_turn_rules(
        _rule_tuple(Val(N), getparam(spec, :phase_noise, ()), :phase_noise), 1, T)
    strength_rules = _resolve_turn_rules(
        _rule_tuple(Val(N), getparam(spec, :strength_noise, ()), :strength_noise), N + 1, T)
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
    _slot_nominals(rules::CrabCavityNoise, base::ThinCrabCavity{N}) -> Tuple

The `2N` slots' nominal parameters in the order of `_slot_rules`: harmonic
`i`'s `(phase = base.phase[i], strengthX = base.strengthX[i], strengthY =
base.strengthY[i])` for its phase slot (slot `i`) and again for its strength
slot (slot `N + i`), the three parameters the slot's realised value acts on --
`phase + d` on the phase, `strengthX (1 + d)` and `strengthY (1 + d)` on the
strength. The run artifact writes them as `nominal_phase`, `nominal_strengthX`,
`nominal_strengthY` on each active slot's provenance group
(`docs/design/turn_modulation_record.md`, D3 and D7).
"""
function _slot_nominals(rules::CrabCavityNoise, base::ThinCrabCavity{N,M,T}) where {N,M,T}
    harmonic(i) = (phase = base.phase[i], strengthX = base.strengthX[i], strengthY = base.strengthY[i])
    return (ntuple(harmonic, Val(N))..., ntuple(harmonic, Val(N))...)
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
