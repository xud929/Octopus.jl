export BPMObserver, bpm_reading, readings

# ---------------------------------------------------------------------------
# Beam position monitor: what a device would READ, not what the beam IS.
#
# Derivation, the four-code comparison it is drawn from, and the architecture
# decision behind it: `docs/theory/bpm_measurement_model.md`.
#
# A `MomentObserver` reports the truth. A BPM reports a number a real pickup
# would produce, which is what an orbit-correction loop, a beam-based alignment
# routine, or a response-matrix measurement actually consumes.
#
# THIS IS AN OBSERVER, NOT AN ELEMENT, and that is a decision rather than a
# convenience. A BPM offset cannot live in a tracking map: `_misalign_frames`
# builds an entrance map into the body frame and an exit map back to the design
# frame, so for a zero-length element with an identity body they cancel exactly.
# A misaligned `MarkerSpec` really is wrapped in a `MisalignedElement` and
# really does return its input bit for bit. AT hit the same wall and says so in
# `bpm_matrices.m`: "position errors introduced by T1,T2 are not visible since
# the reference orbit is back to nominal."
#
# The deeper reason is that a misalignment says where a FIELD acts. A BPM has no
# field. Its offset moves the origin of the measurement, which changes the
# reported number and never the particle.
# ---------------------------------------------------------------------------

"""
    BPMObserver(name; x_offset=0, y_offset=0, tilt=0, x_gain=0, y_gain=0,
                x_readout=0, y_readout=0, x_noise=0, y_noise=0,
                path=nothing, rng_id=nothing)

A beam position monitor: reads the transverse **centroid** and reports it
through a device error model.

The reading is

    (x, y)_read = G R(tilt) [ (xbar, ybar) - (x_offset, y_offset) ]
                  + (x_readout, y_readout) + (x_noise, y_noise) .* xi

with `G = diag(1 + x_gain, 1 + y_gain)`, `R` a rotation of the measurement axes
about `s`, and `xi` standard normal. `xbar`/`ybar` are means over the surviving
particles, so a BPM under `allow_lost_particles` reads the live beam.

Fields, and which reference code each comes from:

| field | meaning |
|---|---|
| `x_offset`, `y_offset` | where the BPM body sits; a beam on the design axis reads `-offset` (Bmad's sign) |
| `tilt` | roll of the measurement axes about `s` (AT `Rotation`, Bmad `tilt`) |
| `x_gain`, `y_gain` | relative calibration error (MAD-X `MSCALX`, AT `Scale - 1`) |
| `x_readout`, `y_readout` | additive electrical bias (MAD-X `MREX`, AT `Offset`) |
| `x_noise`, `y_noise` | per-reading resolution, one standard deviation (AT `Reading`) |

**Why both an offset and a readout bias**, when for a pure translation either
could absorb the other: they compose differently. The offset sits inside the
rotation and the gain, the bias outside both. That is AT's distinction between
its `t1` and `tb`, and it is physical — a displaced pickup is seen through the
BPM's own rotated and mis-scaled axes, an electronics zero-offset is not.

**Signs are not uniform across the codes and this one had to choose.** A BPM
displaced by `+1` mm reports a beam on the design axis at `-1` mm, so
`x_offset` subtracts. MAD-X's `MREX` and AT's `Offset` add, because those are
reading biases rather than body positions — they are `x_readout` here. Setting
`x_offset` where a MAD-X deck said `MREX` gives the right magnitude and the
wrong sign.

Readings accumulate in memory and are available through
[`readings`](@ref). Passing `path` also appends them to a TSV file.

```julia
bpm = BPMObserver("bpm_01"; x_offset = 1.0e-4, x_noise = 5.0e-6)
task = TrackingTask(line, beam; hooks = [ScheduledObserver(bpm)])
```

Placed in the element line instead of in `hooks`, a `ScheduledObserver` holding
a BPM reads at that point in the line rather than at the end of the turn, which
is what gives a BPM its location.
"""
mutable struct BPMObserver <: AbstractBeamObserver
    name::String
    x_offset::Float64
    y_offset::Float64
    tilt::Float64
    x_gain::Float64
    y_gain::Float64
    x_readout::Float64
    y_readout::Float64
    x_noise::Float64
    y_noise::Float64
    rng_id::Int
    turns::Vector{Int}
    x::Vector{Float64}
    y::Vector{Float64}
    path::Union{Nothing,String}
    initialized::Bool
    # Occurrence bookkeeping for the noise key: which turn was last drawn for,
    # and how many readings that turn has taken so far. `x_noise` is
    # per-reading, so a BPM read twice in one turn must draw twice (audit
    # part 7, T9); the first reading of a turn keeps occurrence 0 and
    # therefore the exact pre-existing stream.
    noise_turn::Int64
    noise_uses::Int
end

function BPMObserver(name::AbstractString="bpm";
                     x_offset::Real=0, y_offset::Real=0, tilt::Real=0,
                     x_gain::Real=0, y_gain::Real=0,
                     x_readout::Real=0, y_readout::Real=0,
                     x_noise::Real=0, y_noise::Real=0,
                     path::Union{Nothing,AbstractString}=nothing,
                     rng_id::Union{Nothing,Integer}=nothing)
    x_noise >= 0 || throw(ArgumentError("x_noise is a standard deviation and must be nonnegative; got $x_noise"))
    y_noise >= 0 || throw(ArgumentError("y_noise is a standard deviation and must be nonnegative; got $y_noise"))
    # An id drawn once at construction, not per reading: it is what makes the
    # noise stream this BPM's own, and distinct from every other stochastic
    # consumer in the run.
    id = rng_id === nothing ? next_rng_id!() : Int(claim_rng_id!(rng_id))
    return BPMObserver(String(name), Float64(x_offset), Float64(y_offset), Float64(tilt),
                       Float64(x_gain), Float64(y_gain),
                       Float64(x_readout), Float64(y_readout),
                       Float64(x_noise), Float64(y_noise), id,
                       Int[], Float64[], Float64[],
                       path === nothing ? nothing : String(path), false,
                       Int64(-1), 0)
end

"""
    bpm_reading(bpm, xbar, ybar, ctx::TrackingContext)
    bpm_reading(bpm, xbar, ybar, turn)

Apply the device model to a centroid and return `(x_read, y_read)`.

!!! warning "This call MUTATES the BPM"
    Reading advances the BPM's occurrence counter, because the noise draw is
    keyed on it (see below), so every later reading of the same BPM **in the
    same turn** gets a different noise sample than it otherwise would. The name
    carries no `!` and this went unstated (2026-08-05_b audit, U7-11).

    It matters for a read-only-looking peek from an action or a hook: measured,
    one `execute!(turns=4)` records
    `[2.09e-5, 6.71e-6, 8.09e-6, -6.93e-6]` on its own and
    `[1.36e-6, -8.95e-7, 4.88e-6, -1.28e-5]` when something peeks each turn.
    The effect is bounded to one `execute!`, because `prepare_observer!` resets
    the counter, which is why it is easy to miss.

Separated from `observe!` because it is the whole physics of the element and is
worth testing without a beam. The noise draw is a function of the context's
RNG snapshot, the turn, the BPM's `rng_id`, and the reading's occurrence index
within the turn -- so a run's readings are fixed at `execute!` time exactly as
stochastic tracking is, and a mid-run `set_global_rng!` cannot retroactively
change them (audit part 7, T8). The convenience `turn` method snapshots the
globals at the call, which is the interactive behaviour it always had.

The rotation reuses `_misalign_matrix`, the routine the misalignments, the
patch and `ref_tilt` all go through, so `tilt = psi` means one thing everywhere
in Octopus. That it also agrees with AT's `[C S; -S C]` and Bmad's `M_m` is a
check on the convention rather than a coincidence -- but note that this is a
rotation of *measurement axes* applied to positions only, not a canonical frame
change, so it shares the convention and nothing else.
"""
function bpm_reading(bpm::BPMObserver, xbar::Real, ybar::Real, ctx::TrackingContext)
    dx = Float64(xbar) - bpm.x_offset
    dy = Float64(ybar) - bpm.y_offset
    W = _misalign_matrix(Float64, 0.0, 0.0, bpm.tilt, false)
    c, s = W[1], W[4]
    ux = c * dx + s * dy
    uy = c * dy - s * dx
    rx = (1 + bpm.x_gain) * ux + bpm.x_readout
    ry = (1 + bpm.y_gain) * uy + bpm.y_readout
    if bpm.x_noise != 0 || bpm.y_noise != 0
        occurrence = _bpm_noise_occurrence!(bpm, ctx.turn)
        # The occurrence rides in the particle slot: a BPM reads the beam, not
        # a particle, so the slot is free -- and occurrence 0 reproduces the
        # stream from before readings were counted.
        n1 = octopus_normal(ctx.seed, ctx.rng_method, ctx.turn, bpm.rng_id, occurrence, 1, Float64)
        n2 = octopus_normal(ctx.seed, ctx.rng_method, ctx.turn, bpm.rng_id, occurrence, 2, Float64)
        rx += bpm.x_noise * n1
        ry += bpm.y_noise * n2
    end
    return rx, ry
end

bpm_reading(bpm::BPMObserver, xbar::Real, ybar::Real, turn::Integer) =
    bpm_reading(bpm, xbar, ybar, TrackingContext(turn=turn))

"""
The reading's occurrence index within `turn`, counted per BPM. Deterministic
given the schedule: the n-th reading of a turn is occurrence n-1 on every run,
which is what keeps noisy readings reproducible and chunk-invariant while
still giving repeated readings of one turn independent draws.
"""
function _bpm_noise_occurrence!(bpm::BPMObserver, turn::Integer)
    if bpm.noise_turn != Int64(turn)
        bpm.noise_turn = Int64(turn)
        bpm.noise_uses = 0
    end
    occurrence = bpm.noise_uses
    bpm.noise_uses += 1
    return occurrence
end

"""
    _bpm_centroid(rep)

Transverse centroid over the surviving particles.

`beam_statistics` would give the same two numbers, but it also builds a full
6x6 covariance, three emittances and optionally fourth moments. A lattice can
hold hundreds of BPMs read every turn, so this takes the two means it needs
through the same masked `_mean` that `beam_statistics` uses -- same reduction,
same lost-particle handling, none of the rest.
"""
function _bpm_centroid(rep)
    # Default path: no host copy at all. `_live_stat_flags` returns `nothing`
    # unless `allow_lost_particles()` is on, and then only x and y are read --
    # but this called `_host_coordinate_arrays(rep)` first, which is `Array(v)`
    # for ALL SIX coordinates. At the production benchmark size that is
    # 6 x 2.56e6 x 8 B = 123 MB copied per reading, for two numbers, in a
    # function whose own docstring justifies itself with "a lattice can hold
    # hundreds of BPMs read every turn" (2026-08-05_b audit, U7-5).
    #
    # `_mean(v)` is `sum(v)/length(v)`, which reduces on the device for a
    # CuArray, so the common case now transfers nothing.
    if !allow_lost_particles()
        return _mean(rep.x), _mean(rep.y)
    end
    # Lost particles allowed: liveness genuinely depends on all six components,
    # so the masked path keeps its host copy. Narrowing that one too needs the
    # device-side mask the CUDA `_moment_observer_row` builds, which is a
    # separate change.
    coords = _host_coordinate_arrays(rep)
    flags = _live_stat_flags(coords)
    nlive = flags === nothing ? length(rep) : count(flags)
    # An all-dead beam reads NaN, deliberately: `_mean` is `s / nlive` and
    # `0.0 / 0` is NaN, which is the honest value for "there is no centroid".
    # That was arrived at by accident and documented nowhere, while the moment
    # observer reaches the same answer through an explicit, commented branch --
    # "An all-dead beam has no moments to report. NaN is the honest value"
    # (2026-08-05_b audit, U7-12). Same behaviour on both, now stated on both,
    # so a future reader does not "fix" the division.
    return _mean(coords[1], flags, nlive), _mean(coords[3], flags, nlive)
end

function observe!(bpm::BPMObserver, ctx::TrackingContext, rep)
    _record_execution!(:observer_output, _observer_backend(),
        (observer=:BPMObserver, name=Symbol(bpm.name), turn=ctx.turn))
    xbar, ybar = _bpm_centroid(rep)
    rx, ry = bpm_reading(bpm, xbar, ybar, ctx)
    push!(bpm.turns, ctx.turn)
    push!(bpm.x, rx)
    push!(bpm.y, ry)
    if bpm.path !== nothing
        # First write truncates off a per-object latch, and
        # `_bpm_discard_window!` later rewrites the WHOLE file from this
        # object's memory -- both the U7-10 shape (N3 extension).
        bpm.initialized || _register_observer_path!(bpm, bpm.path)
        open(bpm.path, bpm.initialized ? "a" : "w") do io
            bpm.initialized || println(io, "turn\tx\ty")
            println(io, ctx.turn, '\t', rx, '\t', ry)
        end
        bpm.initialized = true
    end
    return nothing
end

"""
    readings(bpm)

The accumulated readings as `(turns, x, y)`. Returns the observer's own arrays,
so copy them if the run continues and a stable snapshot is wanted.
"""
readings(bpm::BPMObserver) = (bpm.turns, bpm.x, bpm.y)

"""
Discard readings at or beyond `first_turn`, so re-running a turn window is
idempotent instead of appending duplicate turn labels.

Readings ahead of the window can exist for exactly two reasons: a previous
`execute!` failed mid-window (its stored turn deliberately does not advance,
so the retry replays the same absolute turns -- audit part 7, T6), or the
caller rewound with `start_turn` to replay from a checkpoint. In both cases
the timeline from `first_turn` on is being rewritten, and a table carrying two
rows labelled with the same turn is corrupt for every downstream reader. For
an ordinary chunked run every stored turn is below `first_turn` and this is a
no-op. The TSV mirror is rewritten from memory when anything was dropped,
since an append-only file cannot take anything back.
"""
function _bpm_discard_window!(bpm::BPMObserver, first_turn)
    # The replayed window must also redraw the same noise, so the occurrence
    # counter forgets the failed pass along with its readings.
    bpm.noise_turn = Int64(-1)
    bpm.noise_uses = 0
    isempty(bpm.turns) && return nothing
    any(t -> t >= first_turn, bpm.turns) || return nothing
    keep = findall(t -> t < first_turn, bpm.turns)
    keepat!(bpm.turns, keep)
    keepat!(bpm.x, keep)
    keepat!(bpm.y, keep)
    if bpm.path !== nothing
        open(bpm.path, "w") do io
            println(io, "turn\tx\ty")
            for (t, x, y) in zip(bpm.turns, bpm.x, bpm.y)
                println(io, t, '\t', x, '\t', y)
            end
        end
        bpm.initialized = true
    end
    return nothing
end

# Typed on BPMObserver, so neither method can collide with the
# AbstractBeamObserver fallbacks in BeamObservers.jl (see the NOTE there about
# the overwrite trap). One method per preparation chain: task-level hooks and
# in-line placements.
prepare_observer!(bpm::BPMObserver, runtime_elems, schedule, turns, first_turn) =
    (_bpm_discard_window!(bpm, first_turn); nothing)
prepare_line_observer!(bpm::BPMObserver, schedule, turns, first_turn) =
    (_bpm_discard_window!(bpm, first_turn); nothing)

const _BPM_OBSERVER_OPTION_SCHEMA = (
    name=ConfigurationOptionMeta(String, "bpm", "Monitor identity, carried into readings and execution records.";
        category=:diagnostic, consumer=:bpm_reading),
    x_offset=ConfigurationOptionMeta(Float64, 0.0, "Horizontal position of the BPM body; subtracted from the centroid, so a beam on the design axis reads minus this.";
        category=:diagnostic, consumer=:bpm_reading),
    y_offset=ConfigurationOptionMeta(Float64, 0.0, "Vertical position of the BPM body.";
        category=:diagnostic, consumer=:bpm_reading),
    tilt=ConfigurationOptionMeta(Float64, 0.0, "Roll of the measurement axes about s, in radians.";
        category=:diagnostic, consumer=:bpm_reading),
    x_gain=ConfigurationOptionMeta(Float64, 0.0, "Relative horizontal calibration error; 0.5 makes the reading 1.5x. MAD-X MSCALX.";
        category=:diagnostic, consumer=:bpm_reading),
    y_gain=ConfigurationOptionMeta(Float64, 0.0, "Relative vertical calibration error. MAD-X MSCALY.";
        category=:diagnostic, consumer=:bpm_reading),
    x_readout=ConfigurationOptionMeta(Float64, 0.0, "Additive horizontal readout bias, applied outside the rotation and gain. MAD-X MREX.";
        category=:diagnostic, consumer=:bpm_reading),
    y_readout=ConfigurationOptionMeta(Float64, 0.0, "Additive vertical readout bias. MAD-X MREY.";
        category=:diagnostic, consumer=:bpm_reading),
    x_noise=ConfigurationOptionMeta(Float64, 0.0, "Horizontal reading resolution, one standard deviation. Drawn from the counter RNG by turn, so it is reproducible and chunk-invariant.";
        category=:diagnostic, consumer=:bpm_reading),
    y_noise=ConfigurationOptionMeta(Float64, 0.0, "Vertical reading resolution, one standard deviation.";
        category=:diagnostic, consumer=:bpm_reading),
    rng_id=ConfigurationOptionMeta(Int, 0, "Noise-stream identity. Auto-assigned unique at construction; two BPMs given the same id read the same noise stream, so it is the one field deciding whether monitors share noise (audit part 7, T11).";
        category=:diagnostic, consumer=:bpm_reading),
    path=ConfigurationOptionMeta(Union{Nothing,String}, nothing, "Optional TSV output path; readings are always kept in memory.";
        category=:output, consumer=:observer_output),
)
observer_option_schema(::Type{BPMObserver}) = _BPM_OBSERVER_OPTION_SCHEMA
observer_option_schema(::BPMObserver) = _BPM_OBSERVER_OPTION_SCHEMA

function configuration_report(bpm::BPMObserver)
    entries = ConfigurationEntry[]
    for (field, meta) in pairs(_BPM_OBSERVER_OPTION_SCHEMA)
        value = getproperty(bpm, field)
        # `rng_id` is always shown: its value is auto-assigned and unique, so
        # comparing against a schema default would mark it active by accident
        # of the counter rather than by intent.
        active = field === :path ? value !== nothing :
                 (field === :name || field === :rng_id) ? true : value != meta.default
        push!(entries, ConfigurationEntry(field, value, value,
            active ? :resolved : :inactive_dependency,
            active ? "active BPM reading configuration" :
                     "default leaves this term out of the reading",
            meta.consumer))
    end
    return Tuple(entries)
end
