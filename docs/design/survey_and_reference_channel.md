# The Survey and Reference-Energy Channel

> **Status: design, pre-implementation (2026-08-13).** This note records the
> architecture decision for the channel that tells a runtime element where it
> sits on the reference trajectory — the accumulated arc position `s` and,
> later, the local reference momentum `P0`. It is the shared prerequisite of
> two open `docs/todo.md` items: the RF velocity-slip defect (F16, the
> 2026-08-05 audit) and RF Scope B (the accelerating cavity). The physics
> derivations live in
> [`theory/rf_cavity_and_reference_energy.md`](../theory/rf_cavity_and_reference_energy.md)
> and
> [`theory/lattice_hamiltonian_and_conventions.md`](../theory/lattice_hamiltonian_and_conventions.md);
> this note deliberately does not repeat them. It records *which* design was
> chosen among several that achieve similar physics, and why.

## 1. The two consumers, and why they are one channel

**F16.** `_rf_kick` (`src/elements/rf_cavity.jl`) converts between the tracked
longitudinal pair and the cavity's `TIME_ENERGY` frame with its arc position
`s` at the default 0, because a runtime element has no way to know its
accumulated reference path. The dropped term `s·(1/β₀ − 1/β)` is exactly the
velocity-slip contribution to the slip factor, so a ring closed by
`ThinRFCavitySpec` oscillates with `α_c` instead of the full
`η = α_c − 1/γ₀²` — a measured 1.84× synchrotron-tune error at a 2.5 GeV
proton with `α_c = 0.2`, and the wrong side of transition whenever
`α_c < 1/γ₀²`. The fix needs `s = turn·C + s_elem` at kick time.

**Scope B.** An accelerating cavity (Bmad's `lcavity`) changes the reference
energy along the line. Every element downstream needs its local `P0(s)`, and
every energy boundary needs the coordinate rescaling
`p → p·P₀,old/P₀,new` (which *is* adiabatic damping — omitting it leaves each
map individually correct while the emittance is wrong). The theory note's
Scope B list names "a channel for the line to tell an element its local `P0`"
as the item that "does not exist today and is the actual architectural
addition."

These are the same object twice. `P0(s)` is structurally identical to
`s_positions(line)` — one is the energy survey, the other the geometric
survey; both are cumulative design-time passes along the line; both need the
same delivery path from the line into per-element compilation. Scope B's
cavity phase is itself an arrival-time quantity, so F16's requirement is a
strict subset of Scope B's. Building the channel once, with both consumers on
the table, is the fold recorded in `todo.md`.

## 2. The decomposition principle

Every quantity this channel carries factors into a **static per-element part**
and a **dynamic launch-global part**, and the design puts each part where that
kind of state already lives:

| quantity | static per element | dynamic per turn | static home | dynamic home |
|---|---|---|---|---|
| arc position `s` | `s_elem` (line survey) | `turn·C` | runtime op, baked at compile | `TrackingContext.turn` (already exists) |
| reference momentum | `P0_elem` (energy survey, Scope B) | ramp scale (future, §6) | runtime op, baked at compile | knob epoch, *not* the context |

The asymmetry in the last cell is deliberate and argued in §5c/§6: the
per-turn part of `s` is consumed *inside* the kernel (the phase needs it per
kick), while the per-turn part of `P0` must **never** reach a kernel — every
runtime element deliberately holds only dimensionless numbers normalized to
`P0` (`ThinRFCavity.strength = qV/(P₀c)`, the strong-beam `kbb`, …), so a
reference change is a *renormalization*, which is an epoch-boundary recompile,
not a per-particle input.

## 3. The design

### 3a. Static half: the survey pass at compile time

The geometric survey already exists: `s_positions(line)`
(`src/elements/beam_line.jl`), computed rather than cached. What is missing is
delivery. `compile_runtime(spec, method)` is per-element and position-blind;
the compile walk in `src/tasks/Tasks.jl` (`_append_runtime_line!` /
`_runtime_or_existing`) visits entries in line order and is therefore the
natural place to thread an accumulated survey value into each element's
compilation. Elements that declare no interest (all of them today except the
cavity) compile exactly as before.

The compiled `ThinRFCavity` runtime op gains the static values it needs:
`s_elem`, and the per-line constants required for well-conditioned phase
arithmetic (§3c). The **spec layer is untouched**: an element's arc position
is a property of its placement in a line, not of its physics meaning, so per
the two-layer rule it belongs on the compiled runtime object, assigned by the
line walk — never a user-facing spec field that could disagree with the line.

### 3b. Dynamic half: `TrackingContext`, and loud refusal

`TrackingContext` (`src/track/Track.jl`) already carries `turn::Int64`, is
`isbits` for CUDA, and is rebuilt per turn by `execute!` via `with_turn` —
whose docstring anticipated "future scalar context fields." The slip-corrected
cavity becomes a **context-aware op** (the `(op)(ctx, particle_id, coords...)`
protocol) and declares `_requires_tracking_context`, so a contextless
`track!` on a ring containing it is *refused* with an error rather than
silently reverting to `s = 0`. This rides the exact machinery the stochastic
elements already use, and applies the loud-beats-silent rule: the failure mode
of this channel is quiet wrongness, and the refusal is the tripwire.

### 3c. Precision decisions

- `turn` stays the `Int64` it already is; `s` is **never** pre-multiplied into
  a `Float64` handed to the kernel. At 10⁶ turns of a km-scale ring,
  `turn·C ~ 10⁹ m` where Float64 granularity is ~10⁻⁷ m; the phase must
  instead be reduced from the integer — fold `k·C mod 2π` once at compile
  time, multiply by `turn` with the reduction ordered so no intermediate
  carries the full magnitude.
- The post-kick coordinate update must be algebraically rearranged so the
  large `s`-proportional intermediates cancel on paper, not in floating
  point; the implementation must land with a pin at large turn numbers
  (§7) demonstrating the round trip does not degrade with `turn`.
- The time origin is **relative** — phase measured against design arrival —
  per the theory note's §7 decision. Absolute-time tracking and Bmad-style
  autoscale passes are out of scope until a validation contract for them
  exists.

> **Correction (2026-08-14, at implementation).** This subsection planned
> around passing an accumulated arc into the coordinate conversion, and the
> first implementation draft refined that to a bounded per-turn `Δs` — both
> forms are **wrong**, and the second was caught by measurement before
> landing: a constant `s` inside the conversion cancels out of the one-turn
> dynamics entirely (measured `ν_s` stayed at the `α_c`-only value), and an
> accumulating one is the unbounded-state route this subsection was trying
> to avoid. The correct carrier is a **symplectic z-shift at the cavity**,
> `z += Δs·(β/β₀ − 1)` with the exact cancellation-free `g(δ)`, after which
> no turn counter, no `k·C mod 2π` folding, and no context requirement
> exist at all — the correction is a per-op constant. Derivation, the
> negative measurements, and the injection convention:
> [`theory/arc_survey_and_velocity_slip.md`](../theory/arc_survey_and_velocity_slip.md).
> The `TrackingContext.turn` half of §2's table is therefore **unused by
> F16**; it remains correct for consumers that genuinely need absolute turn
> numbering (Scope B's phase bookkeeping may; the stochastic elements do).

## 4. What this channel is *not*: alternatives considered

Several designs achieve similar physics. Each was considered and rejected for
a reason this repository has already paid for somewhere.

**(a) A seventh propagated coordinate (per-particle absolute time or arc).**
Rejected. All four reference codes (Bmad, MAD-X, elegant, AT) treat the
reference as bookkeeping — "nothing propagates a seventh particle" — because
the reference is a *definition*, not a dynamical variable. A seventh
coordinate would touch every kernel signature, every buffer layout, and the
symplectic-pair structure, to carry information that is reconstructible from
`(turn, s_elem)` exactly.

**(b) Velocity slip distributed into every lattice map** (Bmad's `z`
convention, where each drift carries the slip term). Physically equivalent
and internally consistent — but Octopus recorded the opposite convention
choice: the tracked pair is convention #3, whose lattice maps carry no
velocity term *by construction*
(`theory/lattice_hamiltonian_and_conventions.md`), which concentrates the
entire effect into the cavity's coordinate conversion — "the one place it
could have entered." Reversing that now would rewrite the longitudinal
behavior of every map, including every CUDA device-IR path, to fix a defect
that lives at one element kind. Wrong blast radius for the same physics.

**(c) `s` (or `P0`) as `TrackingContext` fields.** Rejected on shape. The
context is one value per launch; `s_elem` and `P0_elem` differ at every
element, so a context-resident value would have to be rewritten between ops
inside the fused per-particle chains — threading a running value to deliver
what is, per line, a static prefix sum. The dynamic-global part (`turn`) is
already there; the static part belongs in the op.

**(d) A stored, mutable per-element reference field** (AT stores `Energy` on
the cavity element; Bmad stores `p0c` on every element, maintained by its
bookkeeping pass). Rejected for this codebase — see §5 for the full
comparison. Octopus's rule is *derive from the one authoritative source*:
`BeamParams` owns `E0`, the line survey owns positions, and runtime ops are
immutable `isbits` values compiled from them. A second stored copy is exactly
the hand-copied state whose staleness this repo's audits keep finding
(`AGENTS.md`, Hard-Won Rules).

**(e) Time-dependent kernels for ramping** (each kernel evaluates `P0(t)`).
Rejected; §6. The reference is bookkeeping, ramps are slow
(`ΔP/P ~ 10⁻⁵–10⁻⁶` per turn), and the quasi-static treatment — constant
within a turn, stepped at epoch boundaries with the §1 rescaling — is both
standard and exactly what the existing epoch machinery provides.

## 5. Position on Bmad's strategy: bookkeeping plus control knobs

Bmad's strategy has three separable parts, and Octopus adopts two of them
while deliberately departing on the third.

**Adopted: the reference is bookkeeping.** No seventh coordinate; a
design-time cumulative pass assigns each element its reference. This note is
that pass, generalized to carry geometry now and energy later. Also adopted:
**two element kinds, not a flag** — `rfcavity` versus `lcavity` — already
followed by Scope A (`ThinRFCavitySpec` is non-accelerating by construction,
and an accelerating cavity is a separate kind for the reason recorded in the
theory note §3). And for multi-pass machines (ERL recirculation), Bmad's
multipass-slave answer — statically unrolling passes so each pass has its own
reference — fits this channel unchanged: each pass compiles its own runtime
instances with its own survey values.

**Adopted, translated: control knobs for time variation.** Bmad's rampers and
elegant's ramp elements make machine variation a *scheduled control-system
action*, not kernel-level time dependence. Octopus's translation is the knob
subsystem plus epochs (`docs/knob_control.md`): element parameters as
expression trees over knobs, knob assignment bumping a global epoch, and the
task layer already recompiling knob-dependent lines when `knob_epoch()` moves
(the compile cache in `src/tasks/Tasks.jl` is keyed on exactly this). A ramp
is a knob on the reference driving renormalization — §6.

**Departed: where the per-element reference *lives*.** Bmad stores `p0c` on
every element as authoritative mutable state, repaired by a bookkeeping pass
whenever the lattice is manipulated. That is the right call for Bmad's
interactive model, where users mutate elements freely and the bookkeeping
pass is the guarantee that the stored copies re-converge. Octopus inverts
the ownership: the authoritative objects are the line survey and
`BeamParams.E0`, the per-element values are *derived at compile time* into
immutable runtime ops, and mutation is expressed as "the epoch moved,
recompile." Same information, different owner. The reasons are local to this
codebase, not criticisms of Bmad: (i) runtime ops must be immutable `isbits`
for the CUDA kernels regardless, so a mutable stored field would be a third
representation, not a simplification; (ii) the measured failure mode here is
stored copies going stale (hand-copied case lists, cached defaults, the
`element_help` drift the audits keep catching) — deriving with a coverage
tripwire is the recorded countermeasure; (iii) an element that stores its own
reference can disagree with `BeamParams.E0`, which is precisely the
disagreement the dimensionless-strength discipline was built to make
unrepresentable.

**Deferred, explicitly: autoscale.** Bmad's `phi0_autoscale` /
`field_autoscale` solve the self-referential phase (RF ↔ closed orbit) by
iteration. The theory note §7 chose the simplest honest cut — relative time,
phase against design arrival — and this design keeps that. An autoscale pass
is a real feature with a real validation burden; per the no-speculative-
features rule it stays out until its contract exists.

## 6. The taxonomy of reference-energy change

The channel, plus the epoch machinery, covers every case without kernel-level
time dependence — this is the "many ways to achieve a similar effect" map,
with the chosen route for each:

1. **Constant reference** (every current element; Scope A + F16): geometric
   survey only. `P0` never varies; the cavity needs `s` alone.
2. **Single-pass profile** (linac, transfer line — Scope B proper): static
   `P0(s)` from the energy survey, baked per element; boundary rescaling at
   each energy step. No dynamic part at all.
3. **Multi-pass at different energies** (ERL): statically unrolled — each
   pass compiles its own instances against its own survey. The *sequencing*
   is repetition, but the essence of Bmad's multipass is not: it is a
   **sharing discipline** — one physical element seen by N passes, where the
   physical quantities (the field: one magnet, one supply; the misalignment:
   the magnet sits where it sits) exist once, while per-pass quantities
   (`p0c`, hence normalized strengths) differ per view. Modeled as two
   independent instances, nothing ties the copies' fields together — retune
   the magnet and someone must remember every copy, the hand-copied-state
   staleness failure again. The Octopus carrier of the sharing is the **knob
   system**: the knob holds the physical quantity (the lord), the per-pass
   specs hold expressions over it with per-pass normalization (the slaves) —
   `pass1.k1 = q·B/P0₁`, `pass2.k1 = q·B/P0₂`, one `B` knob feeding both,
   divergence unrepresentable because the dependency is declared. This is
   the control-room reality stated directly: a machine has no per-element
   truth — the control system owns setpoints, and every element parameter is
   a derived view through the wiring diagram, which is exactly what the knob
   dependency graph is. One caveat repetition does not supply: **inter-pass
   RF phase coherence** (an ERL's energy recovery lives in the ~180° return
   phase set by the pass-to-pass time of flight). Under the relative-time
   choice (§3c) that relationship is an explicit modeled input — naturally a
   knob on the later pass's phase, possibly an expression over the return-arc
   length — never something "run it twice" gets right silently.
4. **Ramping ring**: `P0(s, turn) ≈ P0_profile(s) × ramp(turn)` — the
   within-turn profile is flat to `~10⁻⁵`, so the dynamic part is a global
   per-turn scalar. Route: a knob on the reference; a scheduled action
   assigns it, the epoch bumps, the knob-dependent line recompiles with
   renormalized strengths, and the epoch boundary applies the same
   coordinate rescaling Scope B builds for energy steps (adiabatic damping
   at turn granularity instead of element granularity). **Out of scope for
   the first implementation** — recorded here so the first implementation
   does not foreclose it, and so nobody reaches for kernel time-dependence
   when the epoch route exists. The quasi-static treatment is not an
   approximation of convenience: the reference is *defined* as bookkeeping,
   and a per-turn update with boundary rescaling reproduces ramp physics
   (bucket motion, adiabatic emittance damping) with kernels that never see
   time.

## 7. Validation that must land with the implementation

Per the configuration rules in `AGENTS.md`, the channel lands together with
its consumers, its metadata, its refusal behavior, and effectiveness tests
that observe the values at the consumer boundary:

- **F16 acceptance**: synchrotron tune against the *full*
  `η = α_c − 1/γ₀²` (the theory note's own §8 item 4 criterion), at a
  moderate-energy point where the two differ measurably (the 2.5 GeV /
  `α_c = 0.2` case with its known 1.84× separation), and a
  wrong-side-of-transition case (`α_c < 1/γ₀²`).
- **Refusal**: a contextless `track!` on a line containing a slip-corrected
  cavity errors; the error names the channel. (The `_requires_tracking_context`
  fold must include the new op — extend the existing testset, not a copy.)
- **Survey effectiveness at the consumer**: moving a cavity's position in the
  line moves the phase it computes (perturb `s_elem` → observe the kick), so
  the survey is verified *read*, not merely stored — a stored-but-unread
  survey is exactly the U3-2 class of false negative.
- **Precision pin**: the phase and the coordinate round trip at large turn
  numbers (≥10⁶ turns' worth of `turn·C`) do not degrade with `turn`.
- **Neighbour walk** (the 2026-08-05_b lesson): the compile walk, the fused
  chain builder, the CUDA context path, and the `_requires_tracking_context`
  fold are the named neighbours; each gets re-read after the change, and the
  full-suite gate at CI settings closes the campaign.

Scope B's own contracts (delivered energy profile, damping) are specified at
its implementation; they reuse this section's pattern.
