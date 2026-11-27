# The reference ramp: the reference energy stepped at the turn boundary by a
# scheduled action placed last in the line, the live beam rescaled with it
# (docs/theory/reference_ramp.md; R7 of
# docs/design/machine_description_followups.md, batch C, 2026-11-27).
# Included after the hook types (BeamObservers.jl) and the two state-bound
# features it refuses to share a line with (PhaseSpaceReset.jl,
# ParticleTunes.jl); the snapshot codec's methods for it are in
# src/lattice/toml_hooks.jl with the other hooks'.

export ReferenceRamp, synchronous_phase_program, action_option_schema

"""
    ReferenceRamp(program; reference, start_turn=0, name="", companions=())

The ramp of a synchrotron as a scheduled action placed LAST in the line: the
reference energy ``E_0(n)`` per turn as a program, the live beam rescaled at
every turn boundary where the program steps, the reference knob assigned so
each knob-dependent element renormalises before the next turn
(docs/theory/reference_ramp.md).

`program` is the TOTAL reference energy in eV per turn, entry `i` being the
energy of turn `start_turn + i - 1`; the first entry holds for every turn
before `start_turn` and the last for every turn after the program ends (the
flat top). `reference` is the lattice's `ReferenceParticle`, whose energy
must be a bare knob reference (`E0 = @knob_expr(ramp.E0)`; `p0c`, `gamma0`
or `brho` the same way): the action assigns THAT knob, in the reference's
own spelling, converted from the program's energy through the reference's
`mc2` and `charge`. `companions` are further knob programs assigned at the
same boundaries, `(knob_path => values, ...)` with one value per program
entry (the RF phase program [`synchronous_phase_program`](@ref) builds, a
frequency program, anything the ramp drives); as a window starts (its
refusals passed, before the artifact's machine snapshot is rendered) each
companion is set to its value for the first turn, and afterwards it is
assigned whenever its value for the next turn differs from the knob's.

At the end of turn `n` (the action fires after every element of the turn)
the action reads the knob, and when the program's energy for turn `n + 1`
differs it applies the boundary map of the theory note's section 2 to the
representation on its own backend,

    px' = rho px      py' = rho py      1 + pz' = rho (1 + pz)      x, y, z unchanged

with `rho = P0(n) / P0(n+1)` (`pz' = fma(rho, pz, rho - 1)`, one rounding,
the same instruction on host and device), then assigns the knob, which bumps
the knob epoch; the task's turn loop recompiles the line before turn `n + 1`
tracks (`_runtime_entries_stale`, src/tasks/Tasks.jl). An entry equal to the
knob's value rescales nothing and assigns nothing (no epoch move, no
recompile), so a staircase program recompiles at its steps only. Magnets
given by a normalised strength (`k1 = 1.2`) are not knob-dependent and keep
their optics along the ramp (the magnets track the beam); a cavity built on
the reference (`ThinRFCavitySpec(; voltage, reference = ref)`) follows the
knob through its `strength` and `beta0` expressions, and `harmon=` keeps it
synchronous.

Refused by name: an empty program, an entry that is not finite or not above
`mc2`, a reference whose energy is a number or an expression other than a
bare knob, a companion of another length, a companion naming the reference's
knob, two companions on one knob; at compile, a ramp that is not the last
entry of the top-level line, two ramps, a ramp on a schedule other than
`AlwaysSchedule`, a ramp as a task-level hook (`hooks=`/`actions=`, which run
at the START of a turn), a ramp beside a `PhaseSpaceReset` or particle tunes,
or in a `StrongStrongTask`; at `execute!`, before any turn, a ring cavity
whose `beta0` or `strength` is a plain number (it would keep the
normalisation of one energy), a lattice reference that is not the ramp's,
and a knob whose value is not the program's energy for the window's first
turn. A window that reaches no step of any program warns once. A run divided
across MPI ranks refuses line actions, the ramp included
(`_reject_unsharded_tracking_features`). The `:reference_ramp` receipt per
`execute!` names the program's digest, the window, the energies at its ends
and the steps it holds; `:reference_ramp_recompiles` after the window counts
the recompiles the steps caused.

The `Beam`'s `params.E0` is the energy the beam was BUILT at and does not
follow the ramp; the reference during a run is the knob's value. The
snapshot writes the action under the line's hooks with its program as a bulk
table (`{ sha256, length }`; the sidecar and the artifact's `/machine_tables`
hold it) and `read_machine` rebuilds it.

```julia
@knob ramp.E0 = 2.5e9
ref  = ReferenceParticle(:proton; E0 = @knob_expr(ramp.E0))
E0   = collect(range(2.5e9, 3.5e9; length = 10_001))      # 100 keV per turn
cav  = ThinRFCavitySpec(; harmon = 1, voltage = 2.0e5, phase = asin(0.5), reference = ref)
line = BeamLine("ring", cells..., cav, ReferenceRamp(E0; reference = ref, name = "ramp"))
lat  = Lattice("ring"; line, reference = ref, knob_root = :ramp)
```
"""
struct ReferenceRamp <: AbstractBeamAction
    program::Vector{Float64}
    digest::String
    reference::ReferenceParticle{AbstractKnobExpression}
    knob::Symbol
    start_turn::Int64
    name::String
    companions::Tuple{Vararg{NamedTuple{(:knob, :program, :digest),Tuple{Symbol,Vector{Float64},String}}}}
end

function ReferenceRamp(program::AbstractVector{<:Real}; reference, start_turn::Integer=0,
                       name::AbstractString="", companions=())
    reference isa ReferenceParticle || throw(ArgumentError(
        "ReferenceRamp: `reference` must be the ReferenceParticle the lattice and its cavities " *
        "are built on; got a $(typeof(reference))"))
    energy = reference_energy(reference)
    energy isa KnobRef || throw(ArgumentError(
        "ReferenceRamp: the reference's energy must be a bare knob reference so the ramp can " *
        "assign it (ReferenceParticle(:proton; $(reference.energy_key) = @knob_expr(ramp.E0))); got " *
        (energy isa AbstractKnobExpression ? "the expression $(string(energy))" :
                                             "the number $(repr(energy))")))
    isempty(program) && throw(ArgumentError(
        "ReferenceRamp: the program must hold at least one turn; got an empty vector"))
    values = Float64[Float64(v) for v in program]
    for (i, v) in enumerate(values)
        isfinite(v) || throw(ArgumentError(
            "ReferenceRamp: every program entry must be finite; entry $(i) is $(v)"))
        v > reference.mc2 || throw(ArgumentError(
            "ReferenceRamp: the program is the TOTAL reference energy in eV and must exceed " *
            "mc2 = $(reference.mc2) eV at every turn; entry $(i) is $(v)"))
    end
    knob = energy.path
    comps = NamedTuple{(:knob, :program, :digest),Tuple{Symbol,Vector{Float64},String}}[]
    for (j, c) in enumerate(companions)
        c isa Pair || throw(ArgumentError(
            "ReferenceRamp: each companion is `knob_path => values`; companion $(j) is a $(typeof(c))"))
        path = _knob_path(first(c))
        cv = last(c)
        cv isa AbstractVector{<:Real} || throw(ArgumentError(
            "ReferenceRamp: companion $(path) must hold a vector of numbers, one per program " *
            "entry; got a $(typeof(cv))"))
        length(cv) == length(values) || throw(ArgumentError(
            "ReferenceRamp: companion $(path) holds $(length(cv)) values for a program of " *
            "$(length(values)) turns; give one value per program entry"))
        cvals = Float64[Float64(v) for v in cv]
        bad = findfirst(!isfinite, cvals)
        bad === nothing || throw(ArgumentError(
            "ReferenceRamp: every companion value must be finite; companion $(path) entry " *
            "$(bad) is $(cvals[bad])"))
        path === knob && throw(ArgumentError(
            "ReferenceRamp: companion $(path) names the reference's own knob, which the " *
            "program assigns"))
        any(k -> k.knob === path, comps) && throw(ArgumentError(
            "ReferenceRamp: companion $(path) is given twice"))
        push!(comps, (knob=path, program=cvals, digest=_toml_digest(cvals)))
    end
    return ReferenceRamp(values, _toml_digest(values), reference, knob, Int64(start_turn),
                         String(name), Tuple(comps))
end

Base.:(==)(a::ReferenceRamp, b::ReferenceRamp) =
    a.program == b.program && a.reference == b.reference && a.start_turn == b.start_turn &&
    a.name == b.name && a.companions == b.companions
Base.hash(a::ReferenceRamp, h::UInt) =
    hash((:reference_ramp, a.digest, a.knob, a.start_turn, a.name, map(c -> c.digest, a.companions)), h)

function Base.show(io::IO, ramp::ReferenceRamp)
    print(io, "ReferenceRamp(", length(ramp.program), " turns from turn ", ramp.start_turn,
          ", E0 ", first(ramp.program), " -> ", last(ramp.program), " eV, knob ", ramp.knob)
    isempty(ramp.name) || print(io, ", name = ", repr(ramp.name))
    isempty(ramp.companions) || print(io, ", companions = ", join(string.(c.knob for c in ramp.companions), ", "))
    print(io, ")")
end

"""
    action_option_schema(action_or_type) -> NamedTuple

The structured metadata of an action's constructor options, one
`ConfigurationOptionMeta` per keyword, the action twin of
[`observer_option_schema`](@ref) and [`schedule_option_schema`](@ref).
`validate_configuration_metadata()` requires one for every concrete
`AbstractBeamAction` Octopus defines but `BeamSwapAction`, which holds the
function that provides the replacement beam and has no options to describe.
"""
function action_option_schema end

const _REFERENCE_RAMP_OPTION_SCHEMA = (
    program=ConfigurationOptionMeta(AbstractVector{<:Real}, nothing,
        "The TOTAL reference energy in eV per turn, entry i for turn start_turn + i - 1; the first entry holds before start_turn and the last after the program ends (the flat top). Required.";
        consumer=:reference_ramp),
    reference=ConfigurationOptionMeta(ReferenceParticle, nothing,
        "The lattice's ReferenceParticle, its energy a bare knob reference (E0, p0c, gamma0 or brho = @knob_expr(...)) the ramp assigns in that spelling. Required.";
        consumer=:reference_ramp),
    start_turn=ConfigurationOptionMeta(Int, 0,
        "The turn the program's first entry belongs to.";
        consumer=:reference_ramp),
    name=ConfigurationOptionMeta(String, "",
        "A label for the receipt and the snapshot.";
        consumer=:reference_ramp),
    companions=ConfigurationOptionMeta(Tuple, (),
        "Further knob programs assigned at the same turn boundaries, (knob_path => values, ...), one value per program entry; set to the first turn's value when a window starts.";
        consumer=:reference_ramp),
)
action_option_schema(::Type{ReferenceRamp}) = _REFERENCE_RAMP_OPTION_SCHEMA
action_option_schema(::ReferenceRamp) = _REFERENCE_RAMP_OPTION_SCHEMA

"""
    synchronous_phase_program(program, voltage; charge=1) -> Vector{Float64}

The RF phase per turn that delivers a ramp program's energy steps:
`phi_s(n) = asin((E0(n+1) - E0(n)) / (q V))` for every turn but the last,
whose phase is 0 (no gain once the program ends; the flat top), with `q` the
charge in units of e (signed, as `rf_strength` takes it) and `V` the peak
voltage in volts, for a cavity whose kick enters as `sin(k z1 + phase)`
(`ThinRFCavitySpec`). Refused by name when a step exceeds the voltage's
reach. Pair it with the ramp as a companion program on the cavity's phase
knob, which the ramp sets to the first turn's value when a window starts and
steps with the energy:

    phis = synchronous_phase_program(E0, 2.0e5)
    @knob rf.phi_s = 0.0
    cav  = ThinRFCavitySpec(; harmon = 1, voltage = 2.0e5, phase = @knob_expr(rf.phi_s), reference = ref)
    ramp = ReferenceRamp(E0; reference = ref, companions = ("rf.phi_s" => phis,))
"""
function synchronous_phase_program(program::AbstractVector{<:Real}, voltage::Real; charge::Real=1)
    isempty(program) && throw(ArgumentError(
        "synchronous_phase_program: the program must hold at least one turn"))
    (isfinite(voltage) && voltage != 0) || throw(ArgumentError(
        "synchronous_phase_program: `voltage` must be a finite nonzero peak voltage in volts; got $(voltage)"))
    (isfinite(charge) && charge != 0) || throw(ArgumentError(
        "synchronous_phase_program: `charge` must be a finite nonzero charge in units of e; got $(charge)"))
    qV = Float64(charge) * Float64(voltage)
    phis = zeros(Float64, length(program))
    for i in 1:(length(program) - 1)
        step = Float64(program[i + 1]) - Float64(program[i])
        s = step / qV
        abs(s) <= 1 || throw(ArgumentError(
            "synchronous_phase_program: the step from entry $(i) to $(i + 1) ($(step) eV) exceeds " *
            "the voltage's reach |qV| = $(abs(qV)) eV; raise the voltage or spread the ramp over more turns"))
        phis[i] = asin(s)
    end
    return phis
end

# ---------------------------------------------------------------------------
# The program's value per turn and the reference's spellings.
# ---------------------------------------------------------------------------

"""The program index of `turn`: the entry for `start_turn + i - 1`, clamped to the program's ends (the holds)."""
@inline _ramp_index(ramp::ReferenceRamp, turn::Integer) =
    clamp(Int(turn) - Int(ramp.start_turn) + 1, 1, length(ramp.program))
_ramp_energy(ramp::ReferenceRamp, turn::Integer) = ramp.program[_ramp_index(ramp, turn)]

"""The knob's value for the reference energy `E0`: the energy in the reference's own key (`E0`, `p0c`, `gamma0` or `brho`), by the formulas of `_reference_derive`."""
function _ramp_knob_value(ref::ReferenceParticle, E0::Float64)
    key = ref.energy_key
    key === :E0 && return E0
    key === :gamma0 && return E0 / ref.mc2
    p0c = sqrt((E0 - ref.mc2) * (E0 + ref.mc2))
    key === :p0c && return p0c
    return p0c / (CLIGHT * abs(ref.charge))
end

"""The reference momentum `P0 c` in eV from the knob's value `v` in the reference's key."""
function _ramp_p0c_from_knob(ref::ReferenceParticle, v::Float64)
    key = ref.energy_key
    key === :p0c && return v
    key === :brho && return v * (CLIGHT * abs(ref.charge))
    E0 = key === :E0 ? v : v * ref.mc2
    return sqrt((E0 - ref.mc2) * (E0 + ref.mc2))
end

# ---------------------------------------------------------------------------
# The action: the boundary map and the knob assignment.
# ---------------------------------------------------------------------------

"""
    _ramp_rescale!(rep, rho)

The boundary map of docs/theory/reference_ramp.md section 2 on the
representation's own arrays (host or device): `px`, `py` scaled by `rho`,
`1 + pz` scaled by `rho` as `fma(rho, pz, rho - 1)` (one rounding, the same
instruction on every backend), `x`, `y`, `z` untouched. `rho` is cast to the
coordinates' element type once.
"""
function _ramp_rescale!(rep, rho::Float64)
    _, px, _, py, _, pz = coordinate_arrays(rep)
    T = eltype(pz)
    r = T(rho)
    px .*= r
    py .*= r
    pz .= fma.(r, pz, r - one(T))
    return nothing
end

function apply_action!(ramp::ReferenceRamp, ctx::TrackingContext, rep)
    next = ctx.turn + 1
    target = _ramp_knob_value(ramp.reference, _ramp_energy(ramp, next))
    current = Float64(knob_value(ramp.knob))
    if target != current
        rho = _ramp_p0c_from_knob(ramp.reference, current) /
              _ramp_p0c_from_knob(ramp.reference, target)
        _ramp_rescale!(rep, rho)
        set_knob!(ramp.knob, target)
    end
    i = _ramp_index(ramp, next)
    for c in ramp.companions
        v = c.program[i]
        v == Float64(knob_value(c.knob)) || set_knob!(c.knob, v)
    end
    return nothing
end

# A ramp is a per-turn program, not a schedule's business: the compile refuses
# any schedule but AlwaysSchedule (`_check_reference_ramp_placement`), and a
# task-level placement by name here, where the message can say where it goes.
_push_task_hook!(actions, observers, hook::ReferenceRamp) = _refuse_task_level_ramp()
_push_task_hook!(actions, observers, hook::ScheduledAction{<:ReferenceRamp}) = _refuse_task_level_ramp()
_refuse_task_level_ramp() = throw(ArgumentError(
    "a ReferenceRamp cannot be a task-level hook (hooks=, actions=): task-level actions run at " *
    "the START of a turn, before the cavity's kick, and the ramp must step the reference after " *
    "the turn's last element. Place it last in the line: BeamLine(\"ring\", elements..., ramp) " *
    "or (elements..., ramp)."))

# ---------------------------------------------------------------------------
# The compile walk: where a ramp may sit, and what it may not sit beside.
# ---------------------------------------------------------------------------

_is_ramp_entry(entry) = entry isa LineActionEntry && entry.action.action isa ReferenceRamp

"""
    _reference_ramp_of(entries::Tuple) -> Union{Nothing,ReferenceRamp}

The one ramp of a compiled line (`_check_reference_ramp_placement` has
refused a second), or `nothing`. Unrolled over the heterogeneous entries
tuple like the other task-level walkers.
"""
function _reference_ramp_of(entries::Tuple)
    found = Ref{Any}(nothing)
    _foreach_unrolled(entries) do entry
        found[] === nothing && _is_ramp_entry(entry) && (found[] = entry.action.action)
        nothing
    end
    return found[]
end

"""
    _check_reference_ramp_placement(entries::Tuple) -> nothing

Once per compile (`_runtime_entries`), over the compiled line: a
`ReferenceRamp` is the LAST entry of the top-level line (it steps the
reference after the turn's last element; a mid-line placement would leave the
elements after it on the old normalisation for the rest of the turn), there
is one, it runs on `AlwaysSchedule` (the program decides per turn), and it
shares the line with neither a `PhaseSpaceReset` nor particle tunes, whose
state binds to one compiled line while the ramp recompiles the line at every
step. Each refused by name with the remedy.
"""
function _check_reference_ramp_placement(entries::Tuple)
    positions = Int[]
    for (i, entry) in enumerate(entries)
        _is_ramp_entry(entry) && push!(positions, i)
    end
    isempty(positions) && return nothing
    length(positions) == 1 || throw(ArgumentError(
        "this line holds $(length(positions)) ReferenceRamp actions (entries " *
        "$(join(positions, ", ")) of $(length(entries)) in the compiled line); one ramp " *
        "drives the reference, so place exactly one"))
    i = only(positions)
    entry = entries[i]
    entry.action.schedule isa AlwaysSchedule || throw(ArgumentError(
        "the ReferenceRamp is scheduled with $(nameof(typeof(entry.action.schedule))); a ramp " *
        "decides per turn from its own program and must run on every turn: place it bare or as " *
        "ScheduledAction(ramp, AlwaysSchedule())"))
    i == length(entries) || throw(ArgumentError(
        "the ReferenceRamp is entry $(i) of $(length(entries)) in the compiled line; it must be " *
        "the LAST entry of the top-level line, so that it steps the reference after the turn's " *
        "last element and every element of the next turn tracks on the new normalisation " *
        "(docs/theory/reference_ramp.md, section 3). Move it to the end of the line."))
    _has_phase_space_reset(entries) && throw(ArgumentError(
        "a ReferenceRamp cannot share a line with a PhaseSpaceReset: the reset's trial ledger " *
        "binds to one compiled line, and the ramp recompiles the line at every step"))
    _has_particle_tunes(entries) && throw(ArgumentError(
        "a ReferenceRamp cannot share a line with particle tunes (ParticleLinear6D): their " *
        "binding lifecycle is per compiled line, and the ramp recompiles the line at every step"))
    return nothing
end

# ---------------------------------------------------------------------------
# The run: the checks before the first turn, the start of a window, the receipt.
# ---------------------------------------------------------------------------

_ramp_describe(ref::ReferenceParticle) =
    "$(ref.energy_key) = $(reference_energy(ref) isa AbstractKnobExpression ? string(reference_energy(ref)) : repr(reference_energy(ref))) " *
    "(charge $(ref.charge), mc2 $(ref.mc2) eV)"

"""
    _check_reference_ramp_run(ramp, task, first_turn) -> nothing

Before any turn of a window runs (and before the artifact commits and the
receipts are recorded): the lattice's reference, when the task was built
from one, is the ramp's (`==`, the structural equality of
`ReferenceParticle`); every ring cavity of the line declares its `beta0` and
`strength` as knob expressions (a plain number would keep the normalisation
of one energy while the reference moves); and the ramp's knob holds the
program's value for `first_turn` (the beam about to be tracked was built at
one reference, and the program must name the same one). Each refused by name
with the remedy; then, the refusals passed, every companion knob is set to
its value for `first_turn`, before the artifact's snapshot is rendered.
"""
function _check_reference_ramp_run(ramp::ReferenceRamp, task::TrackingTask, first_turn::Integer)
    machine = task.machine
    if machine !== nothing
        for lat in machine.lattices
            ref = lat.reference
            ref === nothing && continue
            ref == ramp.reference || throw(ArgumentError(
                "the ReferenceRamp's reference is not the lattice $(repr(lat.name))'s: the ramp " *
                "assigns $(_ramp_describe(ramp.reference)), the lattice declares " *
                "$(_ramp_describe(ref)). Build the ramp with reference = the lattice's " *
                "ReferenceParticle, so one knob is the reference of both."))
        end
    end
    events = Tuple{Float64,Float64,Any}[]
    _collect_spec_s!(events, task.elements, Ref(0.0), Val(:thin_rf_cavity))
    for (s, _, ent) in events, key in (:beta0, :strength)
        v = getparam(ent, key, nothing)
        v isa AbstractKnobExpression || throw(ArgumentError(
            "the ring cavity at s = $(s) m declares $(key) = $(repr(v)), a plain number, beside " *
            "a ReferenceRamp: it would keep the normalisation of one energy while the reference " *
            "moves. Build it on the ramp's reference (ThinRFCavitySpec(...; voltage, reference " *
            "= ref)) so its strength and beta0 follow the knob."))
    end
    expected = _ramp_knob_value(ramp.reference, _ramp_energy(ramp, first_turn))
    current = Float64(knob_value(ramp.knob))
    current == expected || throw(ArgumentError(
        "the ReferenceRamp's program gives $(ramp.reference.energy_key) = $(expected) for turn " *
        "$(first_turn) (E0 = $(_ramp_energy(ramp, first_turn)) eV), but knob $(ramp.knob) holds " *
        "$(current): the beam about to be tracked was built at one reference and the program " *
        "names another. Set the knob to the program's value " *
        "(set_knob!($(repr(string(ramp.knob))), $(expected))) and build the beam on it, or " *
        "start the program where the reference is."))
    # The ramp's own refusals are behind us: every companion knob takes its
    # value for the first turn NOW, before the artifact's machine snapshot is
    # rendered, so the snapshot's knob values are the window's (a knob
    # already there is left alone, so the epoch does not move for nothing).
    i0 = _ramp_index(ramp, first_turn)
    for c in ramp.companions
        v = c.program[i0]
        v == Float64(knob_value(c.knob)) || set_knob!(c.knob, v)
    end
    return nothing
end

"""
    _start_reference_ramp!(ramp, policy, first_turn, turns) -> nothing

After the last refusal of `_execute_tracking_task!`, beside the per-run
receipts: the window's steps are counted (the turn boundaries inside the
window where the energy program or a companion changes value; the
boundary after the window's last turn included, whose recompile falls to
the next window), a window that reaches none warns once by name, and the
`:reference_ramp` receipt records the program's digest, the window and the
energies at its ends. The companions were set for the first turn by
`_check_reference_ramp_run`, before the artifact's snapshot.
"""
function _start_reference_ramp!(ramp::ReferenceRamp, policy, first_turn::Integer, turns::Integer)
    i0 = _ramp_index(ramp, first_turn)
    # The boundaries n -> n+1 of the window whose program index moves are
    # exactly the index pairs (k, k+1) for k from the first turn's index to
    # the index of the turn after the last one, minus one; the holds at the
    # program's ends move no index and step nothing.
    i1 = _ramp_index(ramp, first_turn + turns)
    steps = 0
    for k in i0:(i1 - 1)
        if ramp.program[k] != ramp.program[k + 1] ||
           any(c -> c.program[k] != c.program[k + 1], ramp.companions)
            steps += 1
        end
    end
    last_turn = first_turn + turns - 1
    steps == 0 && @warn(
        "the ReferenceRamp $(repr(ramp.name)) steps nothing in this window: turns $(first_turn) " *
        "to $(last_turn) reach no change of its program (turns $(ramp.start_turn) to " *
        "$(ramp.start_turn + length(ramp.program) - 1)); the reference holds at E0 = " *
        "$(_ramp_energy(ramp, first_turn)) eV for the whole window")
    _record_execution!(:reference_ramp, backend_type(policy), (
        name=ramp.name, knob=ramp.knob, energy_key=ramp.reference.energy_key,
        start_turn=ramp.start_turn, length=length(ramp.program), sha256=ramp.digest,
        first_turn=Int64(first_turn), turns=Int(turns),
        E0_first=_ramp_energy(ramp, first_turn), E0_last=_ramp_energy(ramp, first_turn + turns),
        steps=steps, companions=Tuple(c.knob for c in ramp.companions)))
    return nothing
end

"""
    _runtime_entries_stale(task::TrackingTask) -> Bool

Whether the compile cache no longer matches the knob and spec epochs: the
per-turn check of the ramp's turn loop (docs/theory/reference_ramp.md,
section 3), one `Ref` read against the epochs `_runtime_entries` recorded.
A line with no knob-dependent element ignores the knob epoch, as the cache
does.
"""
function _runtime_entries_stale(task::TrackingTask)
    cached = task.runtime_entries_cache[]
    cached === nothing && return true
    _, knob_dependent, kepoch, sepoch, _, _ = cached
    return (knob_dependent && kepoch != knob_epoch()) || sepoch != _spec_epoch()
end

# ---------------------------------------------------------------------------
# The knob roots: the ramp's knobs are binding sites of the line (D7).
# ---------------------------------------------------------------------------

function _knob_binding_sites!(out, ramp::ReferenceRamp, ordinal)
    site = "ReferenceRamp" * (isempty(ramp.name) ? "" : " \"$(ramp.name)\"")
    push!(out, (site=site, param="reference.$(ramp.reference.energy_key)",
                expr=reference_energy(ramp.reference)))
    for (i, c) in enumerate(ramp.companions)
        push!(out, (site=site, param="companions[$(i)]", expr=KnobRef(c.knob)))
    end
    return out
end
_knob_binding_sites!(out, hook::ScheduledAction, ordinal) =
    _knob_binding_sites!(out, hook.action, ordinal)
