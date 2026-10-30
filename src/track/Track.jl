export AbstractTrackOp, TrackingContext, with_turn, with_index_offset, track_particle

"""
    TrackingContext(; turn=0, seed=global_rng_seed(),
                    rng_method=global_rng_method_code(), index_offset=0)

Immutable execution context passed through tracking workflows and optionally
into per-particle fused tracking. The context is intentionally small and
`isbits` so it can be passed to CUDA kernels. `turn` identifies the current
turn, while `seed` and `rng_method` snapshot the current Octopus global RNG
state for stochastic tracking.

`index_offset` is what makes a run divided across MPI ranks draw the same
random numbers as an undivided one. The Octopus counter RNG keys each particle's
stream on its index, so a rank holding global particles `k+1 … k+m` must key
them on `k+i`, not on its own `1 … m`; the offset is that `k`. It is `0` in
every single-process run, which is every run that does not go through a
`MultiProcessExecutionPolicy`.
"""
struct TrackingContext
	turn::Int64
	seed::UInt64
	rng_method::UInt8
	index_offset::Int64
end

TrackingContext(; turn::Integer=0,
	            seed::Integer=global_rng_seed(),
	            rng_method=global_rng_method_code(),
	            index_offset::Integer=0) =
	TrackingContext(Int64(turn), UInt64(seed), rng_method_code(rng_method),
	                Int64(index_offset))

"""
    with_turn(ctx, turn)

Return a copy of `ctx` with a new turn value. Use this helper instead of
manually reconstructing `TrackingContext` so future scalar context fields only
need to be handled in one place.
"""
@inline with_turn(ctx::TrackingContext, turn::Integer) =
	TrackingContext(Int64(turn), ctx.seed, ctx.rng_method, ctx.index_offset)

"""
    with_index_offset(ctx, offset)

Return a copy of `ctx` whose per-particle RNG streams are keyed from `offset`.
Set once per run from the multi-process shard; see `TrackingContext`.
"""
@inline with_index_offset(ctx::TrackingContext, offset::Integer) =
	TrackingContext(ctx.turn, ctx.seed, ctx.rng_method, Int64(offset))

"""
    AbstractTrackOp

Runtime tracking object interface. These objects contain only the data needed by
tracking kernels and are produced from structured element specs by
`compile_runtime`.
"""
abstract type AbstractTrackOp end

# A beam-level operation owns capture/loss lifecycle in TrackingTask. Passing a
# context alone cannot make a scalar tracking entry supply that lifecycle.
_requires_tracking_task(::Any) = false
_requires_tracking_task(spec::AbstractElementSpec) = _requires_tracking_task(typeof(spec))
_requires_tracking_task(elems::Tuple) = any(_requires_tracking_task, elems)

"""
    _required_beam_eltype(op) -> Union{Nothing,Type}

The coordinate element type a runtime element requires of the beam it tracks:
its numeric type parameter, the `T<:Number` every runtime struct with numeric
parameters carries (`LatticeMagnet{M,T,...}`, `ThinMultipole{M,T,N}`,
`Aperture{F,M,R,T}`, `Marker{M,T}`, ...), derived from `typeof(op)` by
`_numeric_type_parameter`; `nothing` only for an object that is not a runtime
element. The wrappers and `CompositeLine` answer with the type of what they
hold (their methods sit beside their structs), which is also the type the
placement wraps are built in. The marker, which has no numeric field, carries
`T` as a bare type parameter so that it answers like every kind (fix I of the
crab-cavity noise audit, 2026-10-17): before, an untyped marker answered
`nothing`, and its placement frames stayed `Float64` inside a `Float32` line.

ONE precision rule for every kind (owner decision 2026-10-16, fix H of the
crab-cavity noise neighbour audit): a beam whose element type differs from an
element's is refused BY NAME when a task compiles its line (`_check_beam_eltype`,
`src/tasks/Tasks.jl`, and the strong-strong twin), in either direction, on both
backends, with the remedy from `_beam_eltype_remedy`; a `Float32` beam needs
`Float32` elements everywhere, built with each kind's `Spec{Float32}` form.
Before it (measured 2026-10-16 over all 31 kinds, fix D) a `Float64` element on
a `Float32` beam promoted and narrowed every coordinate on store on the CPU,
and on CUDA 12 kinds failed at device compile with an `InvalidIRError` (a
kernel branch on a runtime flag -- `_has_survey`, `iszero(strength)`,
`is_excitation` -- returning the beam's tuple type on one side and the
element's on the other) while 19 narrowed silently; the by-name refusal
covered the two modulated cavities and the radiation element only.

The suite derives the set of kinds answering a type from the registry (every
kind but `:line`, whose members carry the type) and pins it both ways; a
runtime struct with two distinct numeric type parameters is refused here so
the derivation never guesses.
"""
_required_beam_eltype(op::AbstractTrackOp) = _numeric_type_parameter(typeof(op))
_required_beam_eltype(op) = nothing

# `@generated`: the search over `T.parameters` runs once per concrete type at
# compile time and the answer is a constant, so the walk that calls this on
# every element of a compiled line allocates nothing (the runtime loop over
# `T.parameters` cost 5 kB per call on a 40-element line of eight types,
# found by the once-per-execute! walk pins when batch 2's units met).
"""
    _numeric_type_parameter(T::Type) -> Union{Nothing,Type}

The one type parameter of the concrete type `T` that is a `Number` type, or
`nothing`; two distinct ones are refused rather than guessed between.
"""
@generated function _numeric_type_parameter(::Type{T}) where {T}
    found = nothing
    for p in T.parameters
        (p isa Type && p <: Number) || continue
        if found !== nothing && p !== found
            msg = "$(nameof(T)) carries two numeric type parameters, $(found) and $(p), so " *
                  "the beam element type it requires cannot be derived; the kind must " *
                  "declare _required_beam_eltype itself"
            return :(throw(ArgumentError($msg)))
        end
        found = p
    end
    return :($found)
end

"""
    _beam_eltype_remedy(op, B) -> String

The remedy `_check_beam_eltype` names for a beam of element type `B` refused by
`op`: the typed forms of the kinds the registry maps to `op`'s runtime type,
DERIVED from `ELEMENT_META_BY_KIND` (`_typed_form_names`) and spelled in the
keyword form every kind has (`QuadrupoleSpec{Float32}(; ...)`), or the beam in
the element's type. A kind whose typed form takes a positional argument the
keyword spelling would hide owns its own method (the crab cavity's `{N,T}`).
"""
function _beam_eltype_remedy(op, ::Type{B}) where {B}
    T = _required_beam_eltype(op)
    forms = _typed_form_names(op)
    element = isempty(forms) ? "the kind's Spec{$(B)}(; ...) form" :
                               join(("$(f){$(B)}(; ...)" for f in forms), " or ")
    return "build the element in the beam's type, $(element), or the beam in $(T) " *
           "(Beam(n, policy, $(T)))"
end

"""
    _typed_form_names(op) -> Vector{String}

The friendly constructor names of every registered kind whose runtime type is
`op`'s (the type's wrapper, `_compiled_matches_runtime`'s rule), sorted: a
`LatticeMagnet` is six kinds' runtime, a `ThinMultipole` seven's.
"""
function _typed_form_names(op)
    W = typeof(op).name.wrapper
    names = String[]
    for meta in values(ELEMENT_META_BY_KIND)
        meta.friendly_constructor === nothing && continue
        any(rt -> rt isa Type && Base.unwrap_unionall(rt).name.wrapper === W,
            values(meta.runtime_types)) || continue
        push!(names, string(nameof(meta.friendly_constructor)))
    end
    return sort!(unique!(names))
end

"""
    CrossBackendRounding

The cross-backend rounding class of one runtime element's one-turn map: for
each of the six coordinates whether the CPU and the CUDA kernels leave it
BITWISE identical or may part in the last bits (the ulp class), the bound the
ulp class is held to, and why. Declared per runtime op type by
`_cross_backend_rounding`; checked by measurement on every registry example by
the suite's "Cross-backend rounding classes" testset and on every instance of
`validation/tracking_backend_consistency.jl`, both through
`_cross_backend_agreement` and `_cross_backend_violations`.

THE RULE, measured 2026-10-17 on an RTX 4500 Ada (fix I of the crab-cavity
noise neighbour audit; logs in `result/audit_crab_noise_2026_10_16/fixes/I/`):
the two backends round the IEEE operations alike -- add, subtract, multiply,
divide, square root, `fma` -- and differ in two ways. (1) The device FUSES a
multiply feeding an add, `a * b + c`, into one FMA with a single rounding
where the host rounds twice (NVPTX contracts by default: 1e5 of 1e5 products
fused, the host's two roundings reproduced on 77% of them), and WHICH multiply
it fuses is the compiler's choice in the surrounding kernel, not the author's:
the drift's radicand `(1+pz)^2 - px^2 - py^2` fused in a bare kernel and not
inside the compiled drift, and the straight drift's `x + px/ps0 L` is bitwise
at `L = 0.5` only because scaling by a power of two is exact (7% of 1e5
particles part at `L = 0.35`, 26% at `L = 100` m). (2) The transcendental
functions (`sin`, `cos`, `exp`, `log`, `atan`, ...) come from two libraries,
libdevice against the host's libm, and disagree by one to three ulp on a few
percent of arguments (`octopus_normal`'s Box-Muller draws: 13-15% of draws).
So a coordinate is bitwise across backends only when its kernel path is free
of both -- never written, or written by single IEEE operations or by
arithmetic exact under any fusion (a thin dipole or quadrupole kick, a
multiply by a constant, a kill to NaN) -- and every other written coordinate is
of the ulp class, whatever a particular fixture shows (a small kick's fused
product rarely moves the last bit of a large coordinate; the octupole example
coincides on 1e5 particles). A kind declares what its kernel does; the
measurement decides, and where they disagreed the declaration changed.

Coordinate classes:

- `:untouched`: the map returns the coordinate as it came -- not written, or
  written back exactly for any finite input (a unit matrix row, a term with a
  zero coefficient) -- so it stays bitwise whatever the other coordinates do:
  the class a line composes on.
- `:bitwise`: written to a new value, through arithmetic that rounds alike on
  both backends, from coordinates that are themselves bitwise (a thin
  quadrupole's `px - k x`, one multiply by a constant).
- `:ulp`: may part in the last bits; held to `ulp_bound` ulps OF THE
  COORDINATE'S SCALE over the beam, `max_i |a_i - b_i| / eps(max_i max(|a_i|,
  |b_i|))`, not per particle, because a coordinate passing through zero makes
  a per-particle ulp count meaningless (`docs/experiences.md`). The bound is
  the measurement on the registry example (400 particles with spread, 3
  turns) times four, rounded up to a power of two, at least 4; a kernel that
  cancels one O(1) intermediate against another carries a large bound, the
  bend's pole-face maps 1697 measured and 8192 declared, the Lorentz boost's
  px 3937 and 16384. The sector bend's body (`px c + ps0 s` against
  `b0 q C1`, 1260) and the solenoid (`L (1 - (1+pz)/ps)`, 768) were of that
  class until fix batch 3 unit K (2026-10-17) formed their momenta and
  path-length excess from small quantities: 10 and 25 since, declared 64
  and 128.

The classes are a property of the kernel's arithmetic for the instance, so
one runtime type answers differently for a drift and a quadrupole, for a
damping-only and an exciting radiation element, for the identity matrix and a
coupled one: the methods read the instance. `why` names the operations.
"""
struct CrossBackendRounding
    x::Symbol
    px::Symbol
    y::Symbol
    py::Symbol
    z::Symbol
    pz::Symbol
    ulp_bound::Int
    why::String
end

const _COORDINATE_NAMES = (:x, :px, :y, :py, :z, :pz)
const _ROUNDING_CLASSES = (:untouched, :bitwise, :ulp)

"""
    _rounding_class(; untouched=(), bitwise=(), ulp=(), ulp_bound=0, why) -> CrossBackendRounding

Build a `CrossBackendRounding` from the three coordinate sets, which must
partition `(:x, :px, :y, :py, :z, :pz)` exactly; `ulp_bound` (ulps of the
coordinate's scale) is required and at least 4 when `ulp` is non-empty and
must be 0 otherwise; `why` must name the operations responsible.
"""
function _rounding_class(; untouched=(), bitwise=(), ulp=(), ulp_bound::Integer=0,
                         why::AbstractString)
    classes = Dict{Symbol,Symbol}()
    for (cls, coords) in ((:untouched, untouched), (:bitwise, bitwise), (:ulp, ulp)), c in coords
        c in _COORDINATE_NAMES || throw(ArgumentError(
            "_rounding_class: unknown coordinate $(repr(c)); the six are $(_COORDINATE_NAMES)"))
        haskey(classes, c) && throw(ArgumentError(
            "_rounding_class: coordinate $(repr(c)) is listed twice, as $(classes[c]) and as $(cls)"))
        classes[c] = cls
    end
    undeclared = Tuple(c for c in _COORDINATE_NAMES if !haskey(classes, c))
    isempty(undeclared) || throw(ArgumentError(
        "_rounding_class: no class for $(undeclared); every coordinate must be declared " *
        "untouched, bitwise or ulp"))
    if isempty(ulp)
        ulp_bound == 0 || throw(ArgumentError(
            "_rounding_class: ulp_bound = $(ulp_bound) with no coordinate of the ulp class; declare 0"))
    else
        ulp_bound >= 4 || throw(ArgumentError(
            "_rounding_class: ulp_bound must be at least 4 ulps of the coordinate's scale when a " *
            "coordinate is of the ulp class; got $(ulp_bound)"))
    end
    isempty(strip(why)) && throw(ArgumentError(
        "_rounding_class: `why` must name the operations responsible for the classes"))
    return CrossBackendRounding((classes[c] for c in _COORDINATE_NAMES)..., Int(ulp_bound), String(why))
end

"""The coordinates `class` declares bitwise across backends (`:untouched` or `:bitwise`)."""
_bitwise_coordinates(class::CrossBackendRounding) =
    Tuple(k for k in _COORDINATE_NAMES if getfield(class, k) !== :ulp)
"""The coordinates `class` declares of the ulp class."""
_ulp_coordinates(class::CrossBackendRounding) =
    Tuple(k for k in _COORDINATE_NAMES if getfield(class, k) === :ulp)
"""The coordinates `class` declares never written."""
_untouched_coordinates(class::CrossBackendRounding) =
    Tuple(k for k in _COORDINATE_NAMES if getfield(class, k) === :untouched)
"""Whether every coordinate of `class` is bitwise across backends."""
_all_bitwise(class::CrossBackendRounding) = isempty(_ulp_coordinates(class))

"""
    _cross_backend_rounding(op) -> CrossBackendRounding

The cross-backend rounding class of the runtime element `op` (see
`CrossBackendRounding` for the rule and the classes). Every concrete runtime
op type owns a method beside its struct; the wrappers and `CompositeLine`
derive theirs from what they hold (`_rounding_written_over`). There is NO
silent default: a type without a method is refused here by name, and the
suite derives the set of types that must declare from the registry's runtime
types and the `AbstractTrackOp` tree, pinned both ways.
"""
_cross_backend_rounding(op::AbstractTrackOp) = throw(ArgumentError(
    "$(nameof(typeof(op))) declares no cross-backend rounding class: every runtime op type " *
    "owns a `_cross_backend_rounding` method stating, per coordinate, whether its CPU and " *
    "CUDA kernels agree bitwise or within a bounded number of ulps and why " *
    "(`CrossBackendRounding`, src/track/Track.jl); the suite derives the set of types that " *
    "must declare from the registry and checks each declaration by measurement"))

"""
    _rounding_written_over(inner, written, ulp_bound, why) -> CrossBackendRounding

The class of a map that WRITES the coordinates `written` through fused or
transcendental arithmetic around the map whose class is `inner`: the written
coordinates are of the ulp class, the others keep the inner's class, the bound
is the larger of the two. Used by the frame wrappers (`MisalignedElement`,
`RefTilted`).
"""
function _rounding_written_over(inner::CrossBackendRounding, written, ulp_bound::Integer, why::AbstractString)
    cls(k) = k in written ? :ulp : getfield(inner, k)
    return CrossBackendRounding((cls(k) for k in _COORDINATE_NAMES)...,
                                max(Int(ulp_bound), inner.ulp_bound), String(why))
end

"""
    _rounding_through(inner, why) -> CrossBackendRounding

The inner's classes unchanged, with `why` appended: a wrapper whose own
arithmetic is exact on both backends (a transverse translation, the host-side
realisation of a turn-modulation rule).
"""
_rounding_through(inner::CrossBackendRounding, why::AbstractString) =
    CrossBackendRounding((getfield(inner, k) for k in _COORDINATE_NAMES)..., inner.ulp_bound,
                         inner.why * "; " * String(why))

"""
    _cross_backend_rounding(ops::Tuple) -> CrossBackendRounding

The class of a LINE of runtime elements tracked in order (a task's compiled
tuple, a `CompositeLine`'s members), composed from the members' classes: a
coordinate no member writes stays bitwise (`:untouched`); a written one is
bitwise only when every member is bitwise, because an ulp parted in one
member's output is the next member's input and spreads through every
coordinate that member reads (a drift reads the momenta into x, y and z); the
bound is the members' largest. Host-side reflection, never on a kernel path.
"""
function _cross_backend_rounding(ops::Tuple)
    members = Any[_cross_backend_rounding(op) for op in ops]
    isempty(members) && return _rounding_class(untouched=_COORDINATE_NAMES,
                                               why="an empty line: the identity")
    all_bitwise = all(_all_bitwise, members)
    cls(k) = all(m -> getfield(m, k) === :untouched, members) ? :untouched :
             all_bitwise ? :bitwise : :ulp
    bound = all_bitwise ? 0 : maximum(m.ulp_bound for m in members)
    whys = unique!(String[m.why for m in members])
    return CrossBackendRounding((cls(k) for k in _COORDINATE_NAMES)..., bound,
        "a line of $(length(members)) member(s): a coordinate no member writes stays bitwise; " *
        "the written ones mix through the members and are of the ulp class unless every member " *
        "is bitwise. Members: " * join(whys, " | "))
end

"""
    _cross_backend_agreement(rep_a, rep_b) -> NamedTuple

The measured agreement of two tracked representations (the same beam through
the same line on two backends), per coordinate: `bitwise` (every particle
`===`, a lost particle NaN on both sides included), `max_abs` and `scale`
(`max_i max(|a_i|, |b_i|)`) over the particles finite on both backends,
`ulps_of_scale = max_abs / eps(scale)` -- the quantity a `CrossBackendRounding`
bound is stated in -- `lost_one_backend` (NaN on one side only) and
`compared`. Host-side: both arrays are copied to the host.
"""
function _cross_backend_agreement(rep_a, rep_b)
    rows = Any[]
    for (k, (da, db)) in enumerate(zip(coordinate_arrays(rep_a), coordinate_arrays(rep_b)))
        a = Array(da)
        b = Array(db)
        length(a) == length(b) || throw(ArgumentError(
            "_cross_backend_agreement: coordinate $(_COORDINATE_NAMES[k]) has $(length(a)) " *
            "particles on one backend and $(length(b)) on the other"))
        bitwise = true
        max_abs = 0.0
        scale = 0.0
        lost_one = 0
        compared = 0
        for i in eachindex(a)
            a[i] === b[i] || (bitwise = false)
            av = Float64(a[i])
            bv = Float64(b[i])
            if isnan(av) || isnan(bv)
                (isnan(av) && isnan(bv)) || (lost_one += 1)
                continue
            end
            compared += 1
            max_abs = max(max_abs, abs(av - bv))
            scale = max(scale, abs(av), abs(bv))
        end
        ulps = scale == 0 ? (max_abs == 0 ? 0.0 : Inf) : max_abs / eps(scale)
        push!(rows, _COORDINATE_NAMES[k] => (bitwise=bitwise, max_abs=max_abs, scale=scale,
                                             ulps_of_scale=ulps, lost_one_backend=lost_one,
                                             compared=compared))
    end
    return (; rows...)
end

"""
    _cross_backend_violations(class, agreement; label="element") -> Vector{String}

Every way the measured `agreement` (`_cross_backend_agreement`) contradicts the
declared `class`, each as one sentence naming `label`, the coordinate, the
declaration and the measurement: a bitwise coordinate (`:untouched` or
`:bitwise`) that parted, a ulp-class coordinate beyond its bound, a particle
lost on one backend only, or a coordinate that compared nothing. Empty when the
declaration holds. A `:ulp` coordinate that happens to agree bitwise is NOT a
violation: the class says it may part, not that it does.
"""
function _cross_backend_violations(class::CrossBackendRounding, agreement; label="element")
    found = String[]
    for k in _COORDINATE_NAMES
        a = getfield(agreement, k)
        declared = getfield(class, k)
        a.lost_one_backend == 0 || push!(found,
            "$(label): $(k) is NaN on one backend only for $(a.lost_one_backend) particle(s)")
        a.compared > 0 || push!(found, "$(label): $(k) compared no particle finite on both backends")
        if declared === :ulp
            a.ulps_of_scale <= class.ulp_bound || push!(found,
                "$(label): $(k) is declared :ulp within $(class.ulp_bound) ulps of its scale but " *
                "measured $(a.ulps_of_scale) (max |a - b| = $(a.max_abs), scale = $(a.scale))")
        else
            a.bitwise || push!(found,
                "$(label): $(k) is declared $(repr(declared)), bitwise across backends, but measured " *
                "max |a - b| = $(a.max_abs), $(a.ulps_of_scale) ulps of its scale $(a.scale)")
        end
    end
    return found
end

"""
    _cross_backend_summary(class, agreement) -> String

One line per element for a measurement table: each coordinate as `B` (measured
bitwise) or the measured ulps of scale, with the declared class (`u` for ulp,
`b` for bitwise, `-` for untouched) beside it, then the declared bound.
"""
function _cross_backend_summary(class::CrossBackendRounding, agreement)
    mark(c) = c === :ulp ? "u" : c === :bitwise ? "b" : "-"
    cells = String[]
    for k in _COORDINATE_NAMES
        a = getfield(agreement, k)
        measured = a.bitwise ? "B" : string(round(a.ulps_of_scale; digits=2))
        push!(cells, "$(k)=$(measured)/$(mark(getfield(class, k)))")
    end
    return join(cells, " ") * "  bound=$(class.ulp_bound)"
end

"""
    track_particle(tracking_method, op, x, px, y, py, z, pz)

Per-particle tracking primitive. Implementations dispatch on the tracking
method type, such as `Symplectic6DMap` or `NonSymplectic6DMap`, and a runtime element object. The
method receives one particle as `(x, px, y, py, z, pz)` and returns the updated
six-tuple.
"""
@inline function track_particle(::Type{M}, op::AbstractTrackOp, x0, px0, y0, py0, z0, pz0) where {M<:AbstractTrackingMethod}
	return track_particle(M(), op, x0, px0, y0, py0, z0, pz0)
end

@inline function track_particle(method::M, op::AbstractTrackOp, x0, px0, y0, py0, z0, pz0) where {M<:AbstractTrackingMethod}
	throw(MethodError(track_particle, (method, op, x0, px0, y0, py0, z0, pz0)))
end

@inline function (op::AbstractTrackOp)(ctx::TrackingContext, particle_id,
	                                   x0, px0, y0, py0, z0, pz0)
	return op(x0, px0, y0, py0, z0, pz0)
end

"""
    track_luminous(op, mask, ctx, particle_id, x, px, y, py, z, pz)
        -> ((x, px, y, py, z, pz), (lums...))

Track one particle through `op` AND hand back whatever luminosity it produced,
as a tuple with one entry per luminosity-producing element inside `op` -- empty
for the overwhelming majority of elements, which produce none.

This exists because the fused kernel throws luminosity away. The strong-beam
kernels already compute it (`_thin_strong_beam_track` returns seven values; the
`GaussianStrongBeam` form accumulates over every slice) and then drop it on the
floor, which is why a strong beam has to be pulled OUT of the fused traversal
into its own segment before its luminosity can be recorded at all. The wrappers
drop it for the same reason: each forwards to a six-value `track_particle`.

MASKING HAPPENS HERE, not in the caller, and that is the whole point of the
shape. `_add_luminosity` judges liveness from the coordinates it is handed, and
the rule (`src/track/strong_beam_track.jl`) is to judge the OUTPUT of the kick.
In a fused pass the caller only ever sees end-of-line coordinates, so a caller
that applied the mask would exclude a particle that was alive at the strong beam
and lost at a downstream aperture -- a plausible, slightly wrong luminosity, with
every coordinate digest still bit-identical. Judged here, at the element's own
position, the semantics are exactly the isolated path's.

The default produces nothing and costs nothing: an empty tuple splices away at
compile time.
"""
@inline track_luminous(op, mask, ctx::TrackingContext, particle_id,
                       x, px, y, py, z, pz) =
	(op(ctx, particle_id, x, px, y, py, z, pz), ())

include("fused_track.jl")
