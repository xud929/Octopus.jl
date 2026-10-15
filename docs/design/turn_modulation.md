# Turn-by-turn lattice modulation: the crab cavity noise case

> **Status: stages 1-4 implemented (stages 1 and 2 on 2026-10-12, record
> `../history/turn_modulation_stage1_2026_10_12.md`; stages 3 and 4 on
> 2026-10-13, record `../history/turn_modulation_stages3_4_2026_10_13.md`,
> whose section 6 is the neighbour audit; the two-arm gate ran on b99f6b7 and
> the batch was pushed 2026-10-13 as 6995151, CI run 448 green). First physics
> use 2026-10-14: `examples/crab_cavity_noise.jl` (RF phase and amplitude noise
> on both proton crab cavities of the EIC weak-strong case) with the theory
> note `../theory/crab_cavity_noise_response.md`, which derives the kick
> errors, the IP offsets and the emittance growth the rules drive, and the
> campaign record `../history/crab_cavity_noise_validation_2026_10_14.md`.
> Strength semantics changed 2026-10-15 (owner decision, section 10, stage 0
> of `turn_modulation_record.md`): the `strength_noise` offset is a
> dimensionless relative factor `d` scaling both planes' strengths,
> `S (1 + d)`, on the crab cavity and the RF cavity alike; record
> `../history/crab_cavity_noise_relative_strength_2026_10_15.md`. Stage 1 of
> that note, recording the realised offsets in the run artifact
> (`record_turn_modulation`), landed 2026-10-15 and verified by the
> one-particle probe on CPU threads, CUDA and two MPI ranks (section 4.4;
> record `../history/turn_modulation_record_2026_10_15.md`).**
> Designed
> 2026-10-12 in owner discussion. This note records the architecture decision
> for element parameters that change from one turn to the next inside a
> single tracking run: crab cavity RF phase and amplitude noise first, ramps
> and modulations by the same mechanism. It records which design was chosen
> among several that give the same physics, why, and what was measured to
> decide. Stage 1 landed the pure hook, the wrapper, the white and table rules
> on the crab cavity and tests 1-8 of section 8; where the implementation
> departs from the sketches below (the realised element is the field `inner`,
> the rules are per-harmonic scalar offset generators), section 4.3 and the
> record say so. Every code block below is a demonstration that ran on
> 2026-10-12 against the tree at commit `7711a8a`, before the implementation;
> the numbers quoted are from those runs.

## 1. The problem

A crab cavity's RF phase and voltage jitter turn by turn. Phase noise displaces
the crabbing kick's zero crossing, so a particle at the bunch centre receives a
transverse kick that changes sign randomly from turn to turn; amplitude noise
modulates the kick's slope along the bunch. Both drive emittance growth in a
colliding beam, with a rate set by the noise spectrum at the betatron sidebands
of the revolution frequency and by how the beam-beam force detunes those
sidebands [1, 2]. A noise study therefore needs three things from the tracking
engine: a parameter that takes a different value on every turn, a definite
spectrum for that sequence of values, and reproducibility of the sequence
across chunked, checkpointed, CPU and CUDA runs.

Before stage 1: Octopus's `TrackingTask` does not provide this today. Its
runtime elements are immutable isbits structs compiled once from their specs,
and nothing in the turn loop changes them. The question this note answers is
where the per-turn
variation belongs, given the two-layer design: a polymorphic `ElementSpec`
(physics meaning, metadata, knobs) that `compile_runtime` translates once into
a concrete runtime object carrying exactly what a kernel reads (`AGENTS.md`,
"The spec layer and the runtime layer stay separate").

## 2. What exists, and why none of it fits as is

The relevant seams, read from the tree on 2026-10-12.

**The per-turn element hook.** `update!(elem, ctx::TrackingContext)` is called
once per runtime element at the start of every turn, in fused segments through
`_update_runtime_line!` and in isolated segments directly
(`src/tasks/Tasks.jl`, `_execute_tracking_segment_turn!`). Its docstring names
"turn-dependent ramping, modulation, or cached state" as its purpose. No
element extends it. Its signature is a mutation (`!`, returns `nothing`), and
only two runtime types are mutable, the two strong beams; for every other
element, the crab cavity included, there is nothing the hook could mutate.
(Removed at stage 1; `update`/`update_line` replace it.)

**Scheduled actions.** A `ScheduledAction` runs before a turn, sees the turn
and the particle representation, and may mutate the beam
(`src/tasks/BeamObservers.jl`). It does not see the elements, so it cannot
reach a cavity phase.

**Knobs.** A knob-driven parameter recompiles the line at the next `execute!`
after the knob moves (`docs/knob_control.md`; `_runtime_entries`,
`src/tasks/Tasks.jl`). The gate is checked at the entry of `execute!`, not per
turn, and a recompile rebuilds every element of the line, re-binds apertures
and survey, re-validates the reference chain and empties the plan cache. It is
the right path for a retune between runs and the wrong one for a million
turns: a knob-per-turn loop is correct physics at the cost of a full line
compile per turn.

**Counter-RNG kernels.** `LumpedRad` draws its excitation inside the kernel
from the counter RNG keyed on `(seed, turn, rng_id, particle, component)`
(`src/elements/radiation.jl`), with no mutable state anywhere. That is the
right pattern for a per-particle process. Cavity noise is one number per turn
for the whole beam; drawing it per particle would be correct (every particle
would draw the same value) but it puts an element-level quantity in a
particle-level place and recomputes it `N_particles` times per turn.

**Compile-time wraps.** `compile_runtime` builds the plain runtime element and
then `_misalignment_wrap` and `_ref_tilt_wrap` enclose it in
`MisalignedElement` or `RefTilted` when the spec carries the corresponding
parameters, returning it untouched otherwise (`src/knowledge/Knowledge.jl`,
the compile entry; `src/elements/misalignment.jl`, `src/elements/ref_tilt.jl`).
The wrapper forwards `track_particle`, the context-aware call and
`track_luminous` to the inner element and is "agnostic about what the inner
element does -- magnet, cavity, or anything added later". The task layer knows
the two wrappers by name in four walks (`_inner_method`,
`_hidden_strong_beam_count`, `_descend_strong_beams!`, `_survey_rebind`) and
the BPM observer recognises them. (Stage 1: the walks are checked against a
derived wrapper set; the observer holds no list; see 4.3.)

**The RF-cavity lesson.** `src/elements/rf_cavity.jl` records that an earlier
draft read `ctx.turn` inside the kernel to special-case the injection pass,
which made the raw contextless `track!` path (whose default context pins
`turn = 0`) silently wrong. Any turn-dependent design must leave the
contextless path tracking the nominal element.

**The turn loop already runs one turn per launch.** `_execute_tracking_plan_turn!`
calls `track!` with `turns = 1` for every segment on every turn, and the CUDA
fused kernel receives the element tuple as a launch argument
(`src/track/phase6d_track.jl`, `cuda_track_kernel!`). A tuple whose contents
differ from turn to turn costs the task path nothing extra; only the raw
multi-turn `track!`, which loops inside one kernel launch, could not see such
changes, and it has no update hook anyway.

## 3. Decisions

Each decision names the alternative it rejects.

**D1. The variation is element-owned per-turn state, realised once per turn
on the host.** Not a per-particle kernel draw (rejected: wrong level, redundant
work, and a table-driven sequence cannot be expressed that way at all), and
not a beam action (rejected: cannot reach the element).

**D2. The update resolves on the runtime object, never on the spec.** The spec
declares the rule; `compile_runtime` translates it once into concrete fields;
the per-turn update uses only those fields and the `TrackingContext`. Going
through the spec per turn is the knob path, built for a different time scale
(rejected on cost: a line compile per turn). Consequently turn dependence is
never expressed as a knob expression of the turn.

**D3. The update is a pure, type-preserving function.** `update(elem, ctx)`
returns an element of the same concrete type, `elem` itself for the ordinary
case; the fused tuple is rebuilt each turn from the returned elements. The
mutable-struct alternative (how the strong beams work) is rejected for fused
segments: a mutable element makes the tuple non-isbits and needs a device
adaptor at every launch, while a rebuilt isbits tuple rides into the kernel
parameter space the way the tuple already does. Section 7 measures the
rebuild.

**D4. No new runtime cavity.** `ThinCrabCavity` already carries everything a
kernel reads. What it lacks is the rule for the next turn, and the rule does
not belong in the kernel object. A compile-time wrapper, the third sibling of
`MisalignedElement` and `RefTilted`, holds the nominal element, the realised
element for the current turn, and the rule, and forwards tracking to the
realised element. Adding noise fields to the cavity itself was rejected: it
would have to be repeated for every element that later needs modulation, and
it mixes the rule with the tracking data.

**D5. Nominal and realised values stay separate.** The wrapper keeps the
nominal element untouched and realises a fresh copy every turn, so the
contextless path (no update ever runs) tracks the nominal element, which is
the noiseless cavity. This is the RF-cavity lesson applied.

**D6. The rule interface admits state but does not require it.**
`realize(rule, base, ctx) -> (element, rule′)`. White noise, Voss-McCartney
pink noise, FIR filters on keyed draws and the table rule return themselves as
`rule′`; an IIR filter returns its successor. Section 5 catalogues them with
measured spectra. Qualified at stage 4 (audit lead U1-1): every shipped rule
is a pure function of `ctx` and returns itself, pinned by a tripwire over the
derived rule catalogue (part (k) of the testset "Turn modulation: rules,
wrapper and the pure hook"); the fast loop does not persist a successor
across `execute!` calls (it restarts from the compiled elements on every
call) and the general loop does not persist one across a plan-key flip, so
the interface admits state but nothing yet carries it, and a stateful rule
is an owner decision before it ships: persist successors or forbid state.
The artifact reserves a per-window checkpoint group for such state
(`turn_modulation_record.md`, D10), written by nothing today.

**D7. The table rule is a pure consumer (owner decision, 2026-10-12).** It
takes a vector of per-turn offsets in the slot's own unit (radians on a
phase slot; on a strength slot, since 2026-10-15, dimensionless relative
factors) and nothing else. Spectrum synthesis, the revolution frequency, unit
conversion, normalisation, Gaussianity and periodicity are the data producer's
responsibility and the rule neither checks nor claims them. The rule owns
exactly: the offset semantics (added to a phase, the factor `1 + d` on a
strength), absolute-turn indexing, the length, finiteness
and element-type guardrails, and provenance in the run artifact. The
alternative, a rule that takes a spectrum and a revolution frequency, was
rejected because the revolution frequency is a ring-level quantity the cavity
does not know, and because it would make the consumer responsible for the
producer's modelling choices.

**D8. The rule never reaches the device.** The update runs on the host; the
kernel sees only the realised element. A table of a million turns therefore
lives in host memory with no device copy, and the element tuple handed to CUDA
stays isbits.

## 4. Architecture

### 4.1 Spec layer

Two new parameters on `ElementSpec{:thin_crab_cavity}`, declared in its
`@element_spec` block beside `phase` and the strength tuples, each a tuple of
length `N` mirroring the harmonic-tuple convention:

- `phase_noise`: per harmonic, a rule or `nothing`; unit rad; default a tuple
  of `nothing` (inactive).
- `strength_noise`: per harmonic, a rule or `nothing`; dimensionless, a
  relative factor; default inactive. A single rule per harmonic realises one
  factor `d` and scales both planes' strengths by it, `strengthX (1 + d)` and
  `strengthY (1 + d)`: one voltage driver excites a cavity's horizontal and
  vertical kick, so one relative amplitude error scales both, and a second
  driver is a second cavity (owner decision 2026-10-15, section 10; the RF
  cavity's voltage follows the same convention, `V (1 + d)`). Separate planes
  are not a use case this note knows. Until 2026-10-15 the rule added one
  absolute offset in the strengths' unit to both planes, the default taken in
  the owner's absence, which made a horizontal cavity kick vertically.

Every rule type is a public object with `ParamMeta`-grade metadata (type,
unit, meaning, inactive behaviour) so `element_help`,
`validate_element_metadata()` and the registry snapshot see it. Rules are
data, not programs, in the sense of `docs/knob_control.md`: a rule is a plain
struct with a documented `realize` method, serialisable and reportable.
(Stage 1: the rule types are documented objects, not registry objects, with
no registry root; their metadata is the cavity's `ParamMeta` for `phase_noise`
and `strength_noise`, and the snapshot lists only `TurnModulated`; see 4.3.)

### 4.2 Compile layer

`compile_runtime` for the cavity builds `ThinCrabCavity` as today, then a
`_turn_modulation_wrap(spec, inner)` returns `inner` untouched when every rule
entry is `nothing`, and otherwise `TurnModulated(inner, inner, rules)`. The
order of wraps is modulation innermost, then misalignment, then reference
tilt, because the modulated quantity is the element's own parameter while the
other two wraps act on the frame around the element. The three wrap functions
are called from the same compile entry today's two are.

### 4.3 Runtime layer

```julia
struct TurnModulated{E,R} <: AbstractTrackOp
    base::E       # nominal element, never changes after compile
    current::E    # realised element for the turn being tracked
    rule::R       # how `current` is produced from `base` and the context
end

@inline track_particle(method::AbstractTrackingMethod, w::TurnModulated, x, px, y, py, z, pz) =
    track_particle(method, w.current, x, px, y, py, z, pz)
@inline (w::TurnModulated)(x, px, y, py, z, pz) =
    track_particle(_inner_method(w.current), w.current, x, px, y, py, z, pz)
@inline (w::TurnModulated)(ctx::TrackingContext, pid, x, px, y, py, z, pz) =
    w.current(ctx, pid, x, px, y, py, z, pz)
@inline track_luminous(w::TurnModulated, mask, ctx, pid, x, px, y, py, z, pz) =
    track_luminous(w.current, mask, ctx, pid, x, px, y, py, z, pz)
_inner_method(w::TurnModulated) = _inner_method(w.current)
```

The three forwards are the ones `MisalignedElement` defines; the fourth, the
context-aware call, is the one whose absence on that wrapper once dropped the
context of a wrapped stochastic element (the F13 finding recorded in
`src/elements/misalignment.jl`), so it is defined from the start.

The wrapper joins every walk that names the existing two: `_inner_method`,
`_hidden_strong_beam_count`, `_descend_strong_beams!`, `_survey_rebind`
(which rebinds the nominal `base` once and sets `inner` to it; audit U2-1)
and the suite's wrapper lists. Not the BPM observer: no observer walks
runtime wrappers (`prepare_observer!` ignores the runtime line; the BPM reads
a centroid and draws its reading noise at particle slot = the reading's
occurrence within the turn, components 1-2; audit U2-6, U7-2). The
documentation guide's "derive, don't hand-copy"
invariant applies: the test that enumerates wrappers should derive the set
from the subtypes that forward `track_particle`, with a tripwire, rather than
list three names.

**CUDA.** The wrapper's rule may hold a host array (the table), so the wrapper
is not isbits and must not reach a kernel. Define the device conversion to
drop to the realised element:

```julia
CUDA.cudaconvert(w::TurnModulated) = CUDA.cudaconvert(w.current)
```

`Phase6DRep` converts at launch through `Adapt.@adapt_structure`
(`src/beam/Beam.jl`), and that is the route a kernel argument takes: `@cuda`
converts its arguments with `cudaconvert`, which is `adapt(KernelAdaptor(),
x)` and recurses through tuples via `Adapt.adapt_structure`, so the
conversion is an `Adapt.adapt_structure` method, never a `CUDA.cudaconvert`
one (the `CUDA.cudaconvert(::Phase6DRep)` method once beside it was dead, 0
calls on six launch paths, and was deleted at stage 4; audit U3-1). The
fused tuple containing a wrapper converts to a tuple containing the realised
cavity. **To verify at stage 1:** that the `@cuda` launch applies the
conversion through the nested tuple and that the kernel's element type is the
bare cavity; this is the one untested step of the design.

**Verified at stage 1:** the launch applies the conversion through the tuple,
but only where a method exists. `@cuda` converts its arguments with
`cudaconvert`, which is `adapt(KernelAdaptor(), x)` and recurses through a
tuple element-wise via `Adapt.adapt_structure`, so the conversion is written
as `Adapt.adapt_structure(to, w::TurnModulated) = adapt(to, w.inner)`
(`src/track/phase6d_track.jl`); a `CUDA.cudaconvert(::TurnModulated)` method
as sketched above would not have been reached inside the tuple argument. A
wrapper placed directly in the fused tuple converted and launched with a
non-isbits table rule, and the GPU through the wrapper equalled the GPU and
the CPU through the bare cavity bit for bit. A wrapper nested inside
`CompositeLine`, `MisalignedElement` or `RefTilted` did not: Adapt's default
`adapt_structure` is the identity for a struct it does not know, so the
launch failed with a `KernelError`, "passing non-bitstype argument ... .rule
is of type TurnTable". Fixed with `adapt_structure` methods on the three
containers that descend into what they hold, after which a nested line is
bit-identical GPU against CPU and an updated wrapper tracks its realised
element on the GPU (the suite's "Turn modulation: CPU/CUDA identity and the
device conversion" testset). Two names differ from the sketch above: the
realised element is the field `inner`, not `current`, so that the structural
unwrap in `_compiled_matches_runtime` (`hasfield(:inner)`) and the suite's
derived wrapper set recognise the wrapper without a hand list; and the rules
shipped are per-harmonic scalar offset generators (`WhiteNoise`, `PinkNoise`,
`TurnTable`) held in the crab cavity's container `CrabCavityNoise`, not the
cavity-level `CrabPhaseNoise` of section 5.1. The rule types are documented
public objects, not registry objects: they have no registry root, their
metadata is the cavity's `ParamMeta` for `phase_noise` and `strength_noise`,
and the snapshot lists only `TurnModulated`. The rules' draws sit in their own
band of the counter RNG key, particle slot 0 and component
`_RULE_COMPONENT_BASE + slot` (a pink generator `k` at
`+ _PINK_COMPONENT_STRIDE * (k + 1)`), the layout written down once above that
constant in `src/elements/turn_modulated.jl`: the first draft keyed component
`slot` itself, the cell a noisy BPM's occurrence 0 reads, so a cavity and a
BPM sharing an `rng_id` drew identical normals (review finding S1,
2026-10-12). The keyword constructors follow the radiation convention,
`rng_id = 0` assigns a fresh stream and an explicit id is claimed, so two
`WhiteNoise(1e-2)` without ids, which at first shared stream 0 and warned,
now draw independently as `LumpedRadSpec` and `Beam` do. The band's one
assumption, `2N <= _PINK_COMPONENT_STRIDE`, lived in a comment and a
docstring until stage 4 (audit U7-1): a container with more than 64 slots
let a pink generator's component coincide with another rule's on the same
`rng_id` (N = 33: 64 of 64 draws identical, corr +0.2873; N = 32: 0 of 64,
corr +0.0043). The wrapper constructor `TurnModulated(base, rule)` now
refuses a `PinkNoise` on a container with more than 64 slots and validates
the slot labels (non-empty, no '/', unique), so a crab cavity with more than
32 harmonics may carry white and table rules only. The collision-free layout
(ii), pink generator `k` in particle slot `k` and component
`_RULE_COMPONENT_BASE + slot`, is deferred to the owner: it re-keys every
pink sequence, the stride constant and the keying pin.

### 4.4 Task layer

The hook becomes pure:

```julia
update(elem, ctx::TrackingContext) = elem                         # the default, free
function update(w::TurnModulated, ctx::TrackingContext)
    current, rule = realize(w.rule, w.base, ctx)
    return TurnModulated(w.base, current, rule)
end
@inline update_line(line::Tuple, ctx::TrackingContext) =
    ntuple(i -> (e = line[i]; e isa Tuple ? update_line(e, ctx) : update(e, ctx)), Val(length(line)))
```

`FusedSegment` and `LuminousFusedSegment` hold their tuple in a typed
`Base.RefValue` so the turn loop can store the rebuilt tuple back; the
isolated segment likewise. The existing `update!` is removed rather than kept
beside the new verb (one hook, one meaning); the repo-wide grep the matrix
names for a symbol rename is owed (done at stage 1).

The `ntuple(..., Val(N))` form is load-bearing. `Base.map` over a tuple longer
than 32 elements falls back to a generic path [5]; measured on a 40-element
line it cost 9.6 µs and 79 kB of allocation per turn, against 20 ns and zero
allocation for the unrolled form (section 7). The suite asserts zero
allocation in the rebuild and that the rebuilt tuple's type equals the input
type, in the spirit of the `Core.Box` tripwire.

The offsets each turn's `realize` produces can be recorded in the run
artifact turn by turn (`RunArtifact(path; record_turn_modulation = true)`,
the `series` dataset beside the `/turn_modulation` provenance, fed from the
same evaluation the realised element is built from, so a reader verifies
from the artifact alone that the loop realised a new value every turn and
that the kick consumed it): `turn_modulation_record.md`, stage 1 in
progress 2026-10-15.

### 4.5 Turn indexing

`execute!` carries an absolute turn across calls and `start_turn` repositions
it (`_task_execution_window`, `src/tasks/Tasks.jl`); the context handed to the
hook on the i-th turn of a window starting at `first_turn` has
`ctx.turn == first_turn + i - 1`, zero-based from the task's first ever turn.
Every rule reads that value. The table rule applies entry `ctx.turn + 1`
(one-based storage of a zero-based turn); the first table entry is therefore
the first turn of the run, and a checkpoint restored with `start_turn = N`
reads entry `N + 1`. The documented chunking invariance of the task ("chunked
execution is equivalent to one continuous call for schedules, turn-dependent
elements, and counter-based stochastic tracking", `docs/current_runtime.md`)
is then inherited by every rule, and tested for the first time by a
turn-dependent element.

## 5. Rules

Interface: `realize(rule, base::E, ctx::TrackingContext) -> (E, typeof(rule))`.
The returned element has the same concrete type as `base`. Draws come from the
Octopus counter RNG (`octopus_normal(seed, method, turn, rng_id, index,
component, T)`, `src/math/counter_rng.jl`, Philox4x32 [4]) with the
particle-index slot fixed at 0, so every rule's sequence is a function of
`(seed, rng_id, turn)` and identical on every backend.

### 5.1 White noise (stateless)

One normal per harmonic per turn, keyed on the turn. Sketch; shipped as
per-harmonic `WhiteNoise` entries in `CrabCavityNoise` (4.3).

```julia
struct CrabPhaseNoise{N,T}
    sigma::NTuple{N,T}     # rad per harmonic; zero means that harmonic is quiet
    rng_id::UInt64         # own stream, so two noisy cavities never share draws
end

function realize(rule::CrabPhaseNoise{N,T}, base::ThinCrabCavity{N,M,T}, ctx) where {N,M,T}
    phase = ntuple(N) do i
        n = octopus_normal(ctx.seed, ctx.rng_method, ctx.turn, rule.rng_id, 0, i, T)
        base.phase[i] + rule.sigma[i] * n
    end
    return ThinCrabCavity{N,M,T}(base.method, base.kcc, base.strengthX, base.strengthY, phase), rule
end
```

The demonstration that produced the numbers below drove the low-level
`track!` by hand, one turn per call, since the task plumbing of section 4.4
does not exist yet:

```julia
cavity = compile_runtime(ThinCrabCavitySpec{1}(394.0e6; strengthX=(2.0e-3,), phase=(0.0,)))
line   = (TurnModulated(cavity, cavity, CrabPhaseNoise((1.0e-2,), UInt64(7))),)
rep    = Phase6DRep(randn(1000) * 1e-4, zeros(1000), randn(1000) * 1e-4, zeros(1000), zeros(1000), zeros(1000))
for turn in 1:8
    ctx  = TrackingContext(turn=turn, seed=42)
    line = update_line(line, ctx)
    track!(rep, line, 1; context=ctx)
end
```

Particles at `z = 0` receive no kick from the nominal cavity, so every bit of
centroid motion is the noise. Measured, with the noiseless twin alongside:

```
turn   realized phase [rad]   <px> noisy      <px> noiseless
   1   +2.0085e-03           -4.8647e-07     +0.0000e+00
   2   +2.2566e-03           -1.0330e-06     +0.0000e+00
   3   -2.0900e-03           -5.2682e-07     +0.0000e+00
   4   -6.1631e-03           +9.6588e-07     +0.0000e+00
   5   -6.8644e-03           +2.6284e-06     +0.0000e+00
   6   -1.4883e-02           +6.2331e-06     +0.0000e+00
   7   -3.4575e-03           +7.0704e-06     +0.0000e+00
   8   -1.0113e-02           +9.5198e-06     +0.0000e+00
```

Demonstration keying, component = slot; the shipped rules draw in the band
above `_RULE_COMPONENT_BASE` (section 4.3, stage 1), so the shipped values
differ: see the record's section 3.

Turn 1 matches the kick formula `Δpx = -strength · sin(phase) / k` with
`k = 2π f / c = 8.26 m⁻¹`: `-2e-3 · sin(2.0085e-3) / 8.26 = -4.86e-7`. Each
later row is the running sum, a centroid random walk driven by the phase. The
same seed reproduced the sequence exactly; a different seed did not. The line
tuple was isbits and its type unchanged after every update.

### 5.2 Pink noise, stateless (Voss-McCartney keyed on the turn)

A 1/f process has memory, so it cannot be a pure function of the turn in the
naive way. The Voss-McCartney construction [6, 7] sums `K` octave generators
where generator `k` holds its value for `2^k` turns. That hold is a pure
function of `turn >> k`, so each generator's value is a keyed draw and no
state is carried:

```julia
function pink_vm(turn; K=16)        # 1/f from f_rev / 2^K up to f_rev / 2
    acc = 0.0
    for k in 0:K-1
        acc += normal(turn >> k, k + 1)      # keyed on (seed, turn >> k, rng_id, k)
    end
    return acc / sqrt(K)
end
```

### 5.3 Pink noise, stateful (IIR filter)

White noise through a few first-order poles approximates 1/f over a band. The
economy three-pole filter below is Kellet's [8]; Kasdin [3] gives derived
coefficients for any `1/f^α` as the autoregressive recursion
`a_k = (k - 1 - α/2) · a_(k-1) / k`, truncated at some order. The rule carries
the pole states and returns its successor:

```julia
struct PinkIIR; b0::Float64; b1::Float64; b2::Float64; end
function pink_iir_step(s::PinkIIR, turn)
    w  = normal(turn, 1)
    b0 = 0.99765 * s.b0 + w * 0.0990460
    b1 = 0.96300 * s.b1 + w * 0.2965164
    b2 = 0.57000 * s.b2 + w * 1.0526913
    return (b0 + b1 + b2 + w * 0.1848) * 0.11, PinkIIR(b0, b1, b2)
end
```

What a stateful rule loses is turn addressability: the value at turn `N`
depends on the path, so a checkpoint restore reproduces only if the rule
state is part of the checkpoint, and the sequence needs a burn-in.

### 5.4 FIR on keyed draws (stateless)

`y_t = Σ_k h_k · w_(t-k)` over the previous `n` white inputs. With the counter
RNG the past inputs are not stored data but draws keyed on `t - k`, so an FIR
rule is stateless even though it looks over `n` turns. The weights come from
Kasdin's moving-average recursion `h_k = (k - 1 + α/2) · h_(k-1) / k` for
`1/f^α`, or from the inverse transform of the square root of any target
spectrum. Cost `n` draws per turn; reach about `f_rev / n`. The
Voss-McCartney generator is this idea in disguise, a time-varying FIR on keyed
draws that reaches `2^K` turns with `K` draws at the price of spectral ripple.

### 5.5 Measured spectra of 5.1 to 5.3

Power per octave band of the periodogram over 65,536 turns, normalised to the
top octave; the two lowest bands have too few bins to trust:

```
octave band (f_rev units)        white      pink/VM    pink/IIR
  3.1e-05 .. 6.1e-05           0.000      2.705      0.117
  6.1e-05 .. 1.2e-04           0.000      2.416      0.300
  1.2e-04 .. 2.4e-04           0.001      1.142      1.236
  2.4e-04 .. 4.9e-04           0.001      0.819      1.776
  4.9e-04 .. 9.8e-04           0.002      1.495      1.019
  9.8e-04 .. 2.0e-03           0.005      1.459      1.167
  2.0e-03 .. 3.9e-03           0.007      1.279      0.965
  3.9e-03 .. 7.8e-03           0.016      1.318      1.198
  7.8e-03 .. 1.6e-02           0.029      1.218      1.001
  1.6e-02 .. 3.1e-02           0.062      1.222      0.951
  3.1e-02 .. 6.2e-02           0.124      1.122      1.051
  6.2e-02 .. 1.2e-01           0.251      1.082      1.163
  1.2e-01 .. 2.5e-01           0.505      1.022      1.051
  2.5e-01 .. 5.0e-01           1.000      1.000      1.000

log2 power change per octave: white +1.09   pink/VM -0.11   pink/IIR +0.24
expected:                           +1               0                0
```

Demonstration keying, component = slot; the shipped rules draw in the band
above `_RULE_COMPONENT_BASE` (section 4.3, stage 1), so the shipped values
differ: see the record's section 8.

White doubles per octave as it must. The stateless pink is flat to within a
factor of about 1.3 across twelve octaves, the known ripple of the
construction. The filter is flat over the band it was designed for and rolls
off below about `2e-4 f_rev`. The pink value at turn 40,000 computed cold
equalled the sequential run's, confirming statelessness. A built-in pink rule
must state its approximation band (`K` sets the lowest frequency reached) in
its metadata.

### 5.6 The table rule (stateless, consumer only)

```julia
struct TurnTable{T}
    offsets::Vector{T}      # entry i is the offset on absolute turn i - 1 (rad, or a relative factor)
    digest::UInt64          # recorded in the run artifact
    name::String            # whatever the producer called it; provenance only
end
```

Construction checks: every entry finite, element type equal to the cavity's
numeric type (no silent promotion of a Float32 line), length at least one.
Before the first turn of every `execute!` window the task checks
`first_turn + turns <= length(offsets)` and throws otherwise, so a run never
runs out mid-window and never wraps: a wrapped sequence is periodic in the
table length and would correlate turn `t` with turn `t - N` silently.
`realize` returns `base` with `offsets[ctx.turn + 1]` applied to the nominal
value (added to a phase; on a strength the factor `1 + offsets[ctx.turn + 1]`
on both planes, since 2026-10-15), and the rule unchanged.

What the rule does **not** do, by D7: no spectrum, no revolution frequency, no
units beyond the slot's own (radians on a phase slot; on a strength slot the
dimensionless relative factor, so a strength table holds relative factors and
its entries do not depend on the nominal strength), no Gaussianity check, no
periodicity check. Before 2026-10-15 a producer who wanted relative amplitude
noise multiplied by the nominal strength before handing over the table; under
the relative semantics that table is wrong by the nominal strength.

### 5.7 Summary

| Rule | State carried | Draws per turn | Low-frequency reach | Spectrum control |
|---|---|---|---|---|
| white | none | 1 per harmonic | n/a | none |
| Voss-McCartney pink | none | K | `f_rev / 2^K` | 1/f only, with ripple |
| FIR on keyed draws | none | n | about `f_rev / n` | any, exact to truncation |
| IIR or AR | poles or past outputs | 1 plus p updates | set by the poles | any a low-order filter fits |
| table | none (the table is data) | 1 lookup | the table length | the producer's |

Recommendation: ship white and the table at stage 1, Voss-McCartney pink at
stage 2, and leave FIR and IIR as documented options until a study needs
them. For a study against a measured cavity noise spectrum the table is the
tool; for a parametric `1/f^α` scan, FIR with Kasdin weights on keyed draws is
the clean stateless choice and IIR the fallback when `n` would be too large.

## 6. A producer, for illustration only

This is **not** part of the implementation; it shows what a data producer does
on their side of the D7 boundary, and it is what a future `validation/` helper
could look like. It synthesises a per-turn table from a target one-sided
spectrum `S(f)` in rad²/Hz by frequency-domain shaping (the method of Timmer
and König [9] with fixed amplitudes).

Convention: `N` turns at revolution frequency `f_rev`, bins
`f_k = k · f_rev / N`. For a real sequence with DFT `X_k`, the one-sided
periodogram is `S(f_k) = 2 |X_k|² / (f_rev · N)`, so set
`|X_k| = sqrt(S(f_k) · f_rev · N / 2)` with a random phase per bin, DC zero,
Nyquist real, and invert.

```julia
using FFTW
uniform(k) = octopus_uniform01(SEED, RNG_PHILOX, 0, ID, k, 1)   # bin phase, reproducible

function synthesize(S, N, f_rev)
    nb = N ÷ 2 + 1
    X = zeros(ComplexF64, nb)
    for k in 1:nb-1
        f = k * f_rev / N
        X[k+1] = sqrt(S(f) * f_rev * N / 2) * cis(2pi * uniform(k))
    end
    X[end] = real(X[end])
    return irfft(X, N)
end

f_rev    = 78.2e3                                  # Hz, an EIC-like ring
S(f)     = 1e-9 * (100.0 / f) + 1e-13 + line(f)    # 1/f, white floor, one narrow line at 600 Hz
table    = synthesize(S, 2^20, f_rev)              # 1,048,576 turns
```

Measured on 2026-10-12:

| | value |
|---|---|
| turns | 1,048,576 |
| table memory | 8.4 MB |
| synthesis time | 0.62 s |
| rms phase, table against the integral of `S` | 1.2564e-3 against 1.2564e-3 rad |
| power per octave, table over target | 1.000 in all nineteen bands, the line's band included |
| regenerated from the same seed | identical |

Two modelling choices that belong to the producer and show why D7 puts them
there: fixed amplitudes per bin reproduce the target spectrum exactly, while a
stationary Gaussian process has Rayleigh-distributed amplitudes (multiply by a
complex normal instead of a unit phasor [9]) and matches the target only
statistically; and the synthesised sequence has no power below `f_rev / N` and
is periodic in `N`, so it must be made at least as long as the run.

## 7. Measured cost of the pure update

A compiled Octopus line of alternating crab cavities and `CrabDispersion`
maps, every cavity given a new phase every turn, 100,000 rebuilds, single
thread, 2026-10-12:

| Line | Tuple size | Rebuild per turn | Allocation per turn | One turn of tracking, 10,000 particles, 4 threads |
|---|---|---|---|---|
| 40 elements | 1760 bytes | 20 ns | 0 bytes | 3.4 ms |
| 200 elements | 8800 bytes | 353 ns | 0 bytes | not measured |
| 40 elements, `map` instead of `ntuple(Val)` | 1760 bytes | 9.6 µs | 79 kB | |
| 40 elements, 20 wrapped, `track!` 2000 particles, 4 threads (2026-10-13, audit U1-4) | 4480 bytes wrapped against 3520 bare (+27 %) | 0 B, 2.0 µs in a function (20 Philox draws) | +960 B per worker per turn (20592 against 16752 B) | timing not reproducible on the shared host (the sign of the delta flipped between two runs); a quiet-machine benchmark is owed |
| 40 elements, 20 wrapped, MIXED container `(nothing, WhiteNoise)` on 2 harmonics (2026-10-15, review F1 of the recorder batch) | not measured | not measured | 14400 B per turn before the fix, 15360 B with the recording sink (`(nothing, PinkNoise)` 14720 / 15680 B; the suite's white-pink-plus-table fixture 21120 / 22080 B; per `update` 720 B, 640 B on the main checkout c070750 before the recorder, so pre-existing); 0 B after, on every shape and both hooks | not measured |

The zero in the first rows was measured on HOMOGENEOUS containers (every
slot a `WhiteNoise`), where `rules.phase[i]` has one type whatever `i` is. A
mixed container -- `nothing` beside a rule, a `PinkNoise` -- built its draws
through an `ntuple` closure whose per-index type needed a constant
propagation Julia skips when the closure is not inlineable, so the draws and
the successor inferred as `Union`s and the rebuild allocated (the last row).
Since 2026-10-15 the draws are unrolled with literal indices by `_slot_draws`
(`src/elements/turn_modulated.jl`, `@generated`), 0 B on every shape, and the
suite pins the mixed shapes on both hooks ("Turn modulation: rules, wrapper
and the pure hook", part (d)). `Base.map` over tuples takes its generic path
from 32 entries on, not past 32 (592 B at exactly 32 entries, 0 at 31, Julia
1.12.4), which is why the unrolling is generated rather than mapped.

The rebuild is a stack copy of isbits structs, five orders of magnitude below
one turn of tracking, and the output tuple type equalled the input type in
every case (asserted). The one real cost is compile time: one specialised
rebuild method per distinct line type, of the same order as the fused kernel
already pays for that line. The audit's row measures the wrapper itself
rather than the rebuild: a `TurnModulated` carries `base` and `inner`, so
the fused tuple grows by a cavity per wrapper and each worker copies it once
per turn; coordinates through the wrapped line and through a hand-unwrapped
one are bitwise equal, and the wall-time difference was inside the shared
host's noise, so no timing claim is recorded (a `docs/todo.md` row owes the
quiet-machine number).

## 8. Verification plan

Routed by `AGENTS.md`: the element-spec row (new parameters, metadata, help),
the public-configuration row (rules are public objects with inactive
defaults), the contract row (a new effectiveness contract; superseded at
stage 1: no new contract, the existing `ElementParameterEffectivenessContract`'s
exemption table plus the kernel-boundary testset), the symbol-rename
row (`update!` to `update`), the CUDA row, and the concurrency row (the
rebuild is thread-count invariant by construction but runs inside the fused
path). Full gate, CUDA active, four threads.

Tests the implementation owes, each shown to fail without its feature:

1. **Effectiveness at the kernel boundary.** A white-noise cavity with
   particles at `z = 0` produces the kick `-strength · sin(phase_t) / k` on
   turn `t` for the phase the rule reports, and zero with the rule inactive
   (section 5.1's table as the fixture).
2. **Nominal path.** The contextless `track!` through a `TurnModulated` line
   equals the unwrapped nominal line bit for bit.
3. **Chunking and repositioning.** One `execute!` of `n` turns equals `n`
   calls of one turn, and equals a run restored with `start_turn` at any
   point, for every stateless rule; the IIR rule is tested only for the first
   two with its state carried.
4. **Type stability and allocation.** `typeof(update_line(line, ctx)) ===
   typeof(line)` and zero allocation, on a line longer than 32 elements.
5. **Guardrails.** Table shorter than the window throws before tracking;
   non-finite entries throw at construction; a Float32 line with a Float64
   table throws; two noisy cavities with the same `rng_id` warn, as the
   duplicate radiation stream check does today.
6. **CPU/CUDA identity.** The realised sequence and the tracked coordinates
   agree between backends to the existing near-identity tolerance, and the
   kernel's element type is the bare cavity (the section 4.3 verification).
7. **Wrapper walks.** A derived wrapper set with a tripwire replaces the
   enumerated lists; a noisy misaligned cavity and a noisy cavity inside a
   `BeamLine` track and survey correctly.
8. **Metadata.** `validate_element_metadata()` and
   `validate_configuration_metadata()` pass with the new parameters and rule
   types; both `element_help` forms show them; the snapshot regenerates.
9. **Spectra.** A validation script reproduces section 5.5 for the shipped
   rules with stated tolerances (white slope `+1 ± 0.15`, pink `0 ± 0.2` per
   octave over the trusted bands) and is committed with its record.

## 9. Staging

1. **Hook and wrapper.** `update` replaces `update!`; segments hold their tuple
   by reference; `TurnModulated`, its forwards, the CUDA conversion and the
   derived wrapper set; the white rule and the table rule on the crab cavity
   with their metadata; tests 1 to 8. Full gate.
2. **Pink rule and the spectra script.** Test 9, the validation record, and
   the metadata band statement.
3. **Second element.** The RF cavity's phase and voltage by the same wrap, to
   prove the wrapper is element-agnostic before any generalisation of the
   rule set. (Landed 2026-10-13: scalar `phase_noise`/`strength_noise` on
   `ThinRFCavitySpec`, the slot protocol; see the record.)
4. **Neighbour audit** of the fused path, the wrapper walks and the plan
   cache, as `AGENTS.md` requires at the end of a feature campaign. (Landed
   2026-10-13: seven reading units, two verification passes, 39 leads fixed,
   ledgered or documented; see the record's section 6.)

## 10. Open questions

- Whether a rule should be allowed on a parameter that also carries a knob
  expression (the nominal value from the knob, the offset from the rule). The
  layers make it consistent, since the knob resolves at compile and the rule at
  run time, but it needs a decided answer before stage 1 and a test either way.
  Decided 2026-10-12 in the owner's absence from this note's default (owner
  to confirm): allowed; the knob resolves at compile into the nominal cavity,
  the rule adds its offset at run time, and the knob-composition test pins
  both.
- Whether `strength_noise` should perturb both planes with one realised value
  (this note's assumption) or carry a rule per plane.
  Decided 2026-10-12 in the owner's absence from this note's default (owner
  to confirm): one rule per harmonic, its realised offset added to both
  planes.
  Decided 2026-10-15 by the owner: relative scaling per harmonic, `S (1 + d)`
  on both planes of the crab cavity and on the RF cavity's voltage, one
  voltage driver per cavity; implemented 2026-10-15 as stage 0 of
  `turn_modulation_record.md` (section 7), landed as f7cfe6a and pushed as
  c070750, record
  `../history/crab_cavity_noise_relative_strength_2026_10_15.md`. Why it must
  be decided (2026-10-14, the theory note
  `../theory/crab_cavity_noise_response.md`, sections 3.2 and 8): under this
  semantics a horizontal cavity with `strengthY = 0` acquires vertical
  crabbing noise of the same absolute slope, so at the production point
  (relative amplitude rms 1e-4) the vertical emittance grows at 0.87 of the
  horizontal rate (9.5e-7 against 1.10e-6 per turn), where a physical voltage
  error, scaling both planes proportionally, would give no vertical noise;
  the alternative is a relative (multiplicative) scaling per harmonic. The
  validation sweep measures the vertical rate under the shipped semantics.
- Whether the table may be a `Float32` vector on a `Float64` line with an
  explicit opt-in, for memory on very long runs. Default is to refuse.
  Decided 2026-10-12 in the owner's absence from this note's default (owner
  to confirm): refused at compile, no promotion and no opt-in.

Recording the realised offsets in the run artifact, turn by turn, is designed
in `turn_modulation_record.md` (2026-10-15, not implemented): the switch on
`RunArtifact`, the offsets as the primary datum, the one-particle probe.

## 11. References

1. P. Baudrenghien and T. Mastoridis, "Transverse emittance growth due to rf
   noise in the high-luminosity LHC crab cavities", Phys. Rev. ST Accel.
   Beams 18, 101001 (2015).
2. K. Ohmi, R. Tomás, Y. Funakoshi, R. Calaga, T. Ieiri, Y. Morita,
   K. Nakanishi, K. Oide, Y. Ohnishi, Y. Sun, M. Tobiyama and F. Zimmermann,
   "Response of colliding beam-beam system to harmonic excitation due to
   crab-cavity rf phase modulation", Phys. Rev. ST Accel. Beams 14, 111003
   (2011).
3. N. J. Kasdin, "Discrete simulation of colored noise and stochastic
   processes and 1/f^α power law noise generation", Proc. IEEE 83 (5),
   802–827 (1995).
4. J. K. Salmon, M. A. Moraes, R. O. Dror and D. E. Shaw, "Parallel random
   numbers: as easy as 1, 2, 3", Proc. SC'11 (2011). The Philox4x32 generator
   behind `src/math/counter_rng.jl`.
5. Julia `Base`, `tuple.jl`: `map` over tuples longer than `Any32` (32
   elements) takes the generic, non-unrolled path.
6. R. F. Voss and J. Clarke, "'1/f noise' in music: music from 1/f noise",
   J. Acoust. Soc. Am. 63 (1), 258–263 (1978).
7. J. McCartney's randomised-update variant of the Voss algorithm, as
   described in R. Whittle, "DSP generation of pink (1/f) noise",
   https://www.firstpr.com.au/dsp/pink-noise/ (accessed 2026-10-12).
8. P. Kellet, the "economy" three-pole pink filter, posted to the music-dsp
   mailing list and reproduced in reference 7.
9. J. Timmer and M. König, "On generating power law noise", Astron.
   Astrophys. 300, 707–710 (1995).
10. Octopus: `docs/knob_control.md` (the deferred-expression layer and its
    evaluation point), `docs/design/survey_and_reference_channel.md` (the
    static-at-compile, dynamic-from-context split this note follows, and
    whose §3c is the "design note §3c" that `src/elements/rf_cavity.jl` cites
    for why no kernel reads `ctx.turn` to encode a convention),
    `docs/design/testing_lanes.md` section 3 (the gates).
