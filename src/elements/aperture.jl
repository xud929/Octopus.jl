export ApertureSpec, Aperture, LossRecord, loss_counts, loss_records, aperture_names,
       write_loss_record, read_loss_record, loss_summary

# ---------------------------------------------------------------------------
# Aperture: the element that loses particles.
#
# Design note: `docs/theory/aperture_and_particle_loss.md`. Plan and the
# decisions taken up front: `docs/todo.md`, step 3.
#
# A separate, zero-length element rather than an attribute of every magnet,
# following Xsuite (`LimitRect`) and Elegant (`RCOL`) rather than MAD-X and
# Bmad. It composes with what exists, needs no change to any other element, and
# makes the check location explicit. The price, stated plainly because it
# decides how lattices are built: **loss position is resolved only to where you
# place aperture elements.** A magnet whose entrance and exit both need guarding
# takes two of these, one on each side, and because they are distinct elements
# with distinct ids the log already distinguishes an entrance loss from an exit
# loss -- which is the thing Bmad needs `aperture_at` for.
# ---------------------------------------------------------------------------

"""
    LossRecord

Where apertures record what they killed. One per **beam**, shared by every
aperture in the lattice, because a particle is lost at most once and a
per-element copy would be `O(N)` per aperture.

Two mechanisms at two different rates, which is the point:

- `counts` -- one running total per aperture, bumped on the loss transition.
  `O(1)` per loss. Losses are rare relative to particles, so even an atomic
  increment is negligible here.
- `slots` -- one row per particle, `8` values wide, written at most once. No
  atomics and no cursor: each particle owns its slot, and the loss transition
  fires once ever, so there is no contention. `nothing` when no log path was
  requested, in which case an aperture counts and kills without recording.

The per-particle slot costs `~60 N` bytes per beam and is why it is allocated
only on request. It buys two things a compacting append buffer cannot: slot `i`
is always particle `i`, so CPU and CUDA produce byte-identical records, and `N`
slots is an exact bound that no run can overflow.

Row layout is `(turn, element_id, x, px, y, py, z, pz)`. `element_id == 0` is
the never-lost sentinel, which is what the writer filters on. `particle_id` is
**not** stored: it is the row index. It becomes a column only on output, where
filtering breaks the correspondence.
"""
struct LossRecord{C,S,N}
    counts::C
    slots::S
    names::N
end

LossRecord(counts, slots, names::Vector{String}) =
    LossRecord{typeof(counts),typeof(slots),Vector{String}}(counts, slots, names)

"""Kills attributed to each aperture, indexed by `element_id`."""
loss_counts(record::LossRecord) = Array(record.counts)
loss_counts(::Nothing) = Int[]

"""Aperture names, indexed by `element_id`. Empty on a device-adapted copy."""
aperture_names(record::LossRecord) =
    record.names === nothing ? String[] : record.names
aperture_names(::Nothing) = String[]

if _HAS_ADAPT
    # Hand-written rather than `@adapt_structure` because the names must be
    # *dropped* on the way to the device, not converted: a `Vector{String}` has
    # no device representation, and the kernel has no use for one. It writes an
    # integer id; turning that id back into "COLL_IP6_H" is the host's job at
    # flush time.
    @eval Adapt.adapt_structure(to, record::LossRecord) =
        LossRecord(Adapt.adapt(to, record.counts),
                   Adapt.adapt(to, record.slots),
                   nothing)
end

"""
    LossRecord(names, nparticles, rep; log=true)

Allocate a loss record for one beam, on the same backend as `rep`.

`log=false` allocates counters only. That is the default an aperture gets when
no log path was requested, and it is why an aperture that merely kills costs no
per-particle memory: a dynamic-aperture scan wants survival counts, not
per-particle forensics.
"""
function LossRecord(names::Vector{String}, nparticles::Integer, rep::Phase6DRep;
                    log::Bool=true)
    T = eltype(rep.x)
    na = max(length(names), 1)
    on_cuda = _HAS_CUDA && rep.x isa CUDA.CuArray
    counts = on_cuda ? CUDA.zeros(Int32, na) : zeros(Int32, na)
    slots = if !log
        nothing
    elseif on_cuda
        CUDA.zeros(T, 8, Int(nparticles))
    else
        zeros(T, 8, Int(nparticles))
    end
    return LossRecord(counts, slots, names)
end

"""
    loss_records(record) -> NamedTuple of vectors

The losses actually recorded, one entry per **lost** particle, in particle
order.

This is where storage stops being output. The slots are per particle so that a
kernel can write without contention; the caller wants only the particles that
were lost, and wants to know *which* particles those were -- which the row index
no longer says once the never-lost rows are dropped. So `particle_id` becomes an
explicit column here, and nowhere earlier.
"""
function loss_records(record::LossRecord)
    slots = record.slots
    slots === nothing && throw(ArgumentError(
        "this loss record holds counters only; construct it with a log path to " *
        "record per-particle losses"))
    host = Array(slots)
    lost = [i for i in axes(host, 2) if host[_LOSS_ROW_ELEMENT, i] != 0]
    col(r) = [host[r, i] for i in lost]
    return (particle_id=lost,
            turn=Int.(col(_LOSS_ROW_TURN)),
            element_id=Int.(col(_LOSS_ROW_ELEMENT)),
            x=col(_LOSS_ROW_X + 0), px=col(_LOSS_ROW_X + 1),
            y=col(_LOSS_ROW_X + 2), py=col(_LOSS_ROW_X + 3),
            z=col(_LOSS_ROW_X + 4), pz=col(_LOSS_ROW_X + 5))
end

const _LOSS_ROW_TURN = 1
const _LOSS_ROW_ELEMENT = 2
const _LOSS_ROW_X = 3

"""
    Aperture{F,M,R}

Runtime aperture. Kills a particle that is outside the acceptance by setting all
six of its coordinates to `NaN`, and records the loss when a record is attached.

The three type parameters are all load-bearing:

- `F` is the **type of the `alive` predicate**, not a field typed `Any`. A
  closure stored in an `Any` field is type-unstable and will not compile for the
  GPU; carried in the type it specializes and inlines. `Nothing` selects the
  analytic shape instead.
- `M` is the tracking method, as for every other runtime element.
- `R` is the loss-record type, `Nothing` when no log was requested. This is what
  makes "logging was asked for but the tracking path cannot log" a *dispatch*
  failure rather than a silent omission -- see `_requires_tracking_context`.

An aperture is **not** symplectic: it is a projection, not a map, so it declares
`NonSymplectic6DMap`.
"""
struct Aperture{F,M<:AbstractTrackingMethod,R,T<:AbstractFloat} <: AbstractTrackOp
    method::M
    shape::UInt8        # 1 = rectangle, 2 = ellipse, 3 = rectellipse
    x_limit::T
    y_limit::T
    dx::T
    dy::T
    alive::F
    record::R
    element_id::Int32
end

if _HAS_ADAPT
    # Without this the `record` field reaches the kernel as a host `CuArray` and
    # the launch fails the isbits check.
    @eval Adapt.@adapt_structure Aperture
end

const _APERTURE_RECTANGLE = UInt8(1)
const _APERTURE_ELLIPSE = UInt8(2)
const _APERTURE_RECTELLIPSE = UInt8(3)

const _APERTURE_SHAPE_CODES = Dict(
    :rectangle => _APERTURE_RECTANGLE,
    :ellipse => _APERTURE_ELLIPSE,
    :rectellipse => _APERTURE_RECTELLIPSE,
)

"""
    _aperture_inside(elem, x, y)

Whether `(x, y)` is inside the acceptance, in the aperture's own frame.

Every comparison against `NaN` is false, so a dead particle reads as *outside*
here. That is not how a dead particle is detected -- `_aperture_newly_lost` uses
`isfinite` for that -- but it is why the test needs no separate guard.
"""
@inline function _aperture_inside(elem::Aperture{Nothing}, x, y)
    u = x - elem.dx
    v = y - elem.dy
    a = elem.x_limit
    b = elem.y_limit
    if elem.shape == _APERTURE_RECTANGLE
        return (abs(u) <= a) & (abs(v) <= b)
    elseif elem.shape == _APERTURE_ELLIPSE
        return (u / a)^2 + (v / b)^2 <= one(u)
    else
        return (abs(u) <= a) & (abs(v) <= b) & ((u / a)^2 + (v / b)^2 <= one(u))
    end
end

# Predicate form. It receives all six coordinates in the aperture's frame, so a
# predicate can depend on momentum or on `z` -- an energy collimator is as
# expressible as a transverse one.
@inline _aperture_inside(elem::Aperture{F}, x, px, y, py, z, pz) where {F} =
    elem.alive(x - elem.dx, px, y - elem.dy, py, z, pz)

@inline _aperture_inside(elem::Aperture{Nothing}, x, px, y, py, z, pz) =
    _aperture_inside(elem, x, y)

"""
    _aperture_newly_lost(elem, x, px, y, py, z, pz)

Whether this call is the moment the particle dies: alive on entry, outside on
exit. True exactly once per particle for the whole run, at one aperture.

Detecting the **transition** rather than the condition is what makes logging
idempotent without a per-particle flag. A particle killed on turn `n` stays
`NaN`, and every comparison against `NaN` is false, so on turn `n+1` it reads as
outside the aperture again -- the naive test would re-log it forever. The same
property supplies the fix: a dead particle also fails `isfinite`, so
`was_alive & !inside` is true only on the edge.

`was_alive` tests **all six** coordinates, not just `x` and `y`. Tracking itself
can produce a non-finite particle -- an exact drift takes
`sqrt((1+pz)^2 - px^2 - py^2)`, which goes imaginary once the transverse
momentum exceeds the total -- and such a particle can arrive with `px`
non-finite while `x` is still finite. A two-coordinate test would call it alive
and attribute a numerical blowup to whatever aperture happened to be downstream.
The aperture logs only what it stopped.
"""
@inline function _aperture_newly_lost(elem::Aperture, x, px, y, py, z, pz)
    was_alive = is_live(x, px, y, py, z, pz)
    return was_alive & !_aperture_inside(elem, x, px, y, py, z, pz)
end

@inline _aperture_kill(::Type{T}) where {T} =
    (T(NaN), T(NaN), T(NaN), T(NaN), T(NaN), T(NaN))

# Kill-only path: no context, so no particle id and no turn, so nothing can be
# logged. Defined only for `R === Nothing`; a logging aperture reaching this
# would be a silent failure to record, so it is a dispatch error instead. See
# `_requires_tracking_context`.
@inline function track_particle(::NonSymplectic6DMap, elem::Aperture{F,M,Nothing},
                                x, px, y, py, z, pz) where {F,M}
    _aperture_newly_lost(elem, x, px, y, py, z, pz) || return (x, px, y, py, z, pz)
    return _aperture_kill(typeof(x))
end

@inline (elem::Aperture{F,M,Nothing})(x, px, y, py, z, pz) where {F,M} =
    track_particle(elem.method, elem, x, px, y, py, z, pz)

# Recording path. Reached only through the context-aware call, which is the only
# one carrying the turn and the particle index.
@inline function (elem::Aperture{F,M,<:LossRecord})(ctx::TrackingContext, particle_id,
                                                    x, px, y, py, z, pz) where {F,M}
    _aperture_newly_lost(elem, x, px, y, py, z, pz) || return (x, px, y, py, z, pz)
    _aperture_record!(elem, ctx, particle_id, x, px, y, py, z, pz)
    return _aperture_kill(typeof(x))
end

@inline function _aperture_record!(elem::Aperture{F,M,<:LossRecord}, ctx, particle_id,
                                   x, px, y, py, z, pz) where {F,M}
    record = elem.record
    id = elem.element_id
    _aperture_bump!(record.counts, id)
    slots = record.slots
    slots === nothing && return nothing
    # The coordinates are written *before* the kill overwrites them; that is the
    # whole reason to log here rather than to reconstruct afterwards. What was
    # lost is not recoverable from a beam of NaN.
    @inbounds begin
        slots[_LOSS_ROW_TURN, particle_id] = ctx.turn
        slots[_LOSS_ROW_ELEMENT, particle_id] = id
        slots[_LOSS_ROW_X + 0, particle_id] = x
        slots[_LOSS_ROW_X + 1, particle_id] = px
        slots[_LOSS_ROW_X + 2, particle_id] = y
        slots[_LOSS_ROW_X + 3, particle_id] = py
        slots[_LOSS_ROW_X + 4, particle_id] = z
        slots[_LOSS_ROW_X + 5, particle_id] = pz
    end
    return nothing
end

# The counter is the one place an atomic is warranted: it fires once per loss,
# not once per particle. The private-slot argument that rules atomics out for
# the record does not apply to a single shared cell.
@inline function _aperture_bump!(counts::Array, id)
    @inbounds counts[id] += 1
    return nothing
end

if _HAS_CUDA
    @eval @inline function _aperture_bump!(counts::CUDA.CuDeviceArray, id)
        CUDA.@atomic counts[id] += Int32(1)
        return nothing
    end
end

"""
    _requires_tracking_context(elem)

Whether an element can only run on the context-aware tracking path.

A recording aperture needs the turn and the particle index, and only
`fusedTrack(ctx, elems, particle_id, ...)` carries them. Rather than let a bare
`track!` quietly produce a run with an empty loss log, this is checked once on
the host before the loop and refused. The check is a compile-time constant fold
over the element tuple, so it costs the hot path nothing.
"""
_requires_tracking_context(elem) = false
_requires_tracking_context(elems::Tuple) = any(_requires_tracking_context, elems)
_requires_tracking_context(::Aperture{F,M,<:LossRecord}) where {F,M} = true

"""
    ApertureSpec(; shape, x_limit, y_limit, dx, dy, alive, name)

Aperture element spec. Particles outside the acceptance are killed: all six
coordinates are set to `NaN`, which every downstream map absorbs, so a dead
particle stays dead with no branch anywhere else in the lattice.

Shapes are `:rectangle`, `:ellipse` and `:rectellipse` (their intersection),
sized by `x_limit`/`y_limit` -- the same small regular set MAD-X, Bmad, Xsuite
and Elegant all converged on. Anything else goes through `alive`, a pure scalar
predicate `(x, px, y, py, z, pz) -> Bool` evaluated in the aperture's frame; a
racetrack, an octagon, or an energy collimator are all expressible that way. The
predicate must not capture an array: a polygon lookup table will not run on the
device.

`dx`/`dy` displace the aperture. An aperture belongs to the magnet *body*, so a
displaced magnet carries a displaced aperture, and making the user re-derive
that offset invites silent error. This is deliberately **not** routed through
the misalignment frames: an aperture has no body to tilt through, and rotating a
transverse limit is a shape change rather than a frame change. A rotated
collimator needs `alive`.

`name` is carried for the loss log, so a record says which collimator rather
than which index.

```julia
ApertureSpec(shape=:rectellipse, x_limit=2.0e-2, y_limit=5.0e-3, name="COLL_H")
ApertureSpec(alive=(x, px, y, py, z, pz) -> abs(z) < 0.1, name="Z_SCRAPER")
```

Loss position is resolved only to where you place these. A particle that leaves
the acceptance inside a magnet is not caught until the next aperture downstream.
"""
abstract type ApertureSpec end

ApertureSpec(; kwargs...) = ElementSpec{:aperture}(_spec_params(; kwargs...))

# An aperture is a projection, not a map: it discards part of phase space, so it
# cannot be symplectic and must not inherit the global `Symplectic6DMap` default.
default_method(::Type{ElementSpec{:aperture}}) = NonSymplectic6DMap()

function Aperture(spec::ElementSpec,
                  method::AbstractTrackingMethod=NonSymplectic6DMap())
    alive = getparam(spec, :alive, nothing)
    shape_name = getparam(spec, :shape, :rectangle)
    x_limit = getparam(spec, :x_limit, Inf)
    y_limit = getparam(spec, :y_limit, Inf)
    dx = getparam(spec, :dx, 0)
    dy = getparam(spec, :dy, 0)
    T = float(promote_type(typeof(x_limit), typeof(y_limit), typeof(dx), typeof(dy)))
    if alive === nothing
        haskey(_APERTURE_SHAPE_CODES, shape_name) || throw(ArgumentError(
            "unknown aperture shape $(repr(shape_name)); expected one of " *
            join(sort!(collect(string.(keys(_APERTURE_SHAPE_CODES)))), ", ") *
            ", or supply an `alive` predicate for an irregular shape"))
        x_limit > 0 || throw(ArgumentError(
            "aperture x_limit must be positive; got $(x_limit)"))
        y_limit > 0 || throw(ArgumentError(
            "aperture y_limit must be positive; got $(y_limit)"))
    end
    shape = alive === nothing ? _APERTURE_SHAPE_CODES[shape_name] : UInt8(0)
    record = getparam(spec, :loss_record, nothing)
    element_id = Int32(getparam(spec, :element_id, 0))
    return Aperture{typeof(alive),typeof(method),typeof(record),T}(
        method, shape, T(x_limit), T(y_limit), T(dx), T(dy),
        alive, record, element_id)
end

@element_spec begin
    kind = :aperture
    spec_type = ElementSpec{:aperture}
    friendly_constructor = ApertureSpec
    runtime_type = Aperture
    description = "Zero-length acceptance limit: kills particles outside it by marking them non-finite."
    keywords = [:thin_element, :collimation, :particle_loss]
    tracking_methods = [NonSymplectic6DMap]
    contracts = [ElementTrackingBackendConsistencyContract]
    analyses = [PlaceholderAnalysis]
    parameters = (
        shape=ParamMeta(default=:rectangle, meaning="acceptance shape: :rectangle, :ellipse, or :rectellipse (their intersection). Ignored when `alive` is given"),
        x_limit=ParamMeta(default=Inf, meaning="horizontal half-aperture in particle-coordinate length units"),
        y_limit=ParamMeta(default=Inf, meaning="vertical half-aperture in particle-coordinate length units"),
        dx=ParamMeta(default=0, meaning="horizontal displacement of the aperture, for a collimator on a displaced magnet body"),
        dy=ParamMeta(default=0, meaning="vertical displacement of the aperture"),
        alive=ParamMeta(default=nothing, meaning="pure scalar predicate (x, px, y, py, z, pz) -> Bool evaluated in the aperture frame, for shapes the regular set cannot express. Must not capture an array, or it will not run on the device"),
        name=ParamMeta(default="", meaning="label carried into the loss log so a record names a collimator rather than an index"),
        element_id=ParamMeta(default=0, meaning="identifier stamped into each loss record; assigned by the task from the aperture's position in the compiled line"),
        loss_record=ParamMeta(default=nothing, meaning="per-beam loss record this aperture writes into; supplied by the task, `nothing` means kill and count without recording"),
        tracking_method=ParamMeta(default=NonSymplectic6DMap(), meaning="per-element tracking method"),
    )
    example = ApertureSpec(shape=:rectellipse, x_limit=2.0e-2, y_limit=5.0e-3, name="COLL_H")
    construction_help = "Friendly constructor: ApertureSpec(; shape=:rectangle, x_limit, y_limit, dx=0, dy=0, alive=nothing, name=\"\", tracking_method=NonSymplectic6DMap()). Regular shapes are :rectangle, :ellipse and :rectellipse; anything else goes through `alive`, a pure scalar predicate on all six coordinates. Killed particles become NaN in every coordinate. Loss position resolves only to where you place apertures, so guard both faces of a magnet with two of them. The task supplies element_id and loss_record when it builds the lattice; set neither by hand."
end

const LOSS_RECORD_COLUMNS =
    ["particle_id", "turn", "element_id", "x", "px", "y", "py", "z", "pz"]

"""
    write_loss_record(path, record; s=nothing)

Write the losses to HDF5. **Only the particles that were actually lost.**

Storage and output are different things. The record holds one slot per particle
so that a kernel can write it without contention; the file holds one row per
loss, because that is what a reader wants and because a run losing 1% of a
million particles should not produce a million rows.

That filtering is exactly why `particle_id` is a column here and is stored
nowhere earlier: in the slots it is the row index, and dropping the never-lost
rows destroys that correspondence.

Datasets written:

- `data` -- `nlosses x 9`, columns `LOSS_RECORD_COLUMNS`
- `column_names`
- `record_count`
- `aperture_names`, `aperture_counts` -- the companion mapping from
  `element_id`, so the file says *which collimator* rather than which index.
  Element specs carry no names of their own in Octopus, so without this the ids
  are only interpretable next to the script that produced them.
- `aperture_s` -- longitudinal positions, when the caller can supply them

The format matches `MomentObserver`, so the same tooling reads both.
"""
function write_loss_record(path::AbstractString, record::LossRecord; s=nothing)
    r = loss_records(record)
    n = length(r.particle_id)
    data = Matrix{Float64}(undef, n, length(LOSS_RECORD_COLUMNS))
    for (j, name) in enumerate(LOSS_RECORD_COLUMNS)
        col = getfield(r, Symbol(name))
        @inbounds for i in 1:n
            data[i, j] = Float64(col[i])
        end
    end
    names = aperture_names(record)
    HDF5.h5open(path, "w") do file
        file["data"] = data
        file["column_names"] = LOSS_RECORD_COLUMNS
        file["record_count"] = Int64[n]
        file["aperture_names"] = names
        file["aperture_counts"] = Int64.(loss_counts(record))
        s === nothing || (file["aperture_s"] = collect(Float64, s))
        HDF5.flush(file)
    end
    return n
end

"""
    read_loss_record(path) -> NamedTuple

Read back what `write_loss_record` wrote: one entry per lost particle, plus the
`element_id` mapping needed to say which aperture each loss belongs to.
"""
function read_loss_record(path::AbstractString)
    return HDF5.h5open(path, "r") do file
        data = read(file["data"])
        names = read(file["column_names"])
        cols = Dict(Symbol(name) => data[:, j] for (j, name) in enumerate(names))
        (particle_id=Int.(cols[:particle_id]), turn=Int.(cols[:turn]),
         element_id=Int.(cols[:element_id]),
         x=cols[:x], px=cols[:px], y=cols[:y], py=cols[:py],
         z=cols[:z], pz=cols[:pz],
         aperture_names=read(file["aperture_names"]),
         aperture_counts=read(file["aperture_counts"]),
         aperture_s=haskey(file, "aperture_s") ? read(file["aperture_s"]) : nothing)
    end
end

"""
    loss_summary(rep_or_beam, record) -> NamedTuple

Reconcile the two independent counts of how many particles are gone, and expose
the gap between them.

They are not the same measurement and are not expected to agree:

- `dead` is a beam-wide `!isfinite` reduction over **all six** coordinates,
  `O(N)`, run on whatever cadence the caller likes. It counts every particle
  that is gone, however it went.
- `logged` is the sum of the aperture counters, `O(1)` per loss, free every
  turn. It counts only particles an aperture *stopped*.

`unattributed = dead - logged` is therefore particles that went non-finite with
no aperture responsible -- a numerical blowup in a magnet, an exact drift whose
square root went imaginary, an overflow. Marking losses with `NaN` overloads a
value that has always meant *bug* in this codebase, and this difference is what
keeps the old meaning visible: **a run where these disagree is telling you a
particle died somewhere you did not put a collimator.**

Reporting only `logged` would silently understate the dead; reporting only
`dead` would attribute numerical failures to collimation. The gap is the
diagnostic, so both are returned and never collapsed into one number.
"""
function loss_summary(rep::Phase6DRep, record)
    n = length(rep)
    dead = count_dead(rep)
    logged = isempty(loss_counts(record)) ? 0 : Int(sum(loss_counts(record)))
    return (particles=n, live=n - dead, dead=dead, logged=logged,
            unattributed=dead - logged,
            by_aperture=Int.(loss_counts(record)),
            names=aperture_names(record))
end

loss_summary(beam, record) = loss_summary(beam.rep, record)
