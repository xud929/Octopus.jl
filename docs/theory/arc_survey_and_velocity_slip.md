# The Arc Survey and the Velocity Slip

> **Status (2026-08-14): implemented.** This note is the physics behind the
> geometric survey channel
> ([`design/survey_and_reference_channel.md`](../design/survey_and_reference_channel.md))
> and the F16 velocity-slip closure in `src/elements/rf_cavity.jl`. It
> defines what the survey coordinate *is* (including for curved magnets),
> derives the slip correction in the form the code uses, and records — with
> measurements — the two plausible forms that are **wrong**, one of which
> this project briefly designed before the probe killed it. External check:
> the MAD-X survey consistency contract (`validation/`).

## 1. The survey coordinate

`s` is **arc length along the design orbit**: the accumulated `L` of every
placement ahead of an element, as computed by the one arc walker
(`_collect_spec_s!`, Tasks.jl) that also feeds the aperture arc positions and
agrees entry-for-entry with `s_positions(line)`.

**Curvature changes nothing**, and that is a convention worth stating rather
than assuming: for every curved element (`:sbend`, the curved solenoid — any
kind with frame curvature `h`) the spec's `L` **is the arc length**, the
MAD-X `SBEND` convention this codebase follows throughout (the PTC contract's
bends are constructed the same way). The chord `2/h·sin(hL/2)` is a
*geometric* quantity — where the magnet's ends sit in space — and never a
survey quantity. The one cross-code exception to watch is MAD-X's `RBEND`
(default `RBARC=true`), whose *written* `L` is the chord while its surveyed
arc is longer; Octopus's `RBendSpec` deliberately keeps the one-length rule
(`L` is the arc) and bridges importers with `RBendSpec(chord=…, angle=…)`,
whose construction fold `L = chord·(θ/2)/sin(θ/2)` is pinned against a true
MAD-X rbend by the survey contract's `rbend_chord` fixture at zero measured
deviation. A lattice of bends therefore surveys as plain `L`-sums at
any bend angle, which is exactly what the MAD-X consistency contract pins
externally (MAD-X's `SURVEY` `S` column is the same arc-length sum, while its
`X/Z/THETA` columns are the floor plan the 1D survey deliberately does not
compute).

Two recorded caveats carry over from the aperture walker unchanged:

- a `PatchSpec` carries its path length in `dz`, not `L`, so a line
  containing one reports arc length that omits it — folding `dz` in would be
  wrong as often as right, because a patch displaces a frame in a direction
  that need not lie along the design orbit;
- the walker does not descend a kept-whole (own-state) sub-line — it
  advances by that line's `total_length`, exactly as the compiled runtime
  treats it as one `CompositeLine` op. A cavity inside one is refused loudly
  at bind time rather than silently left uncorrected.

The floor plan proper — global `(X, Y, Z, θ, φ, ψ)` per element, where
curvature *does* rotate the frame — is the geometry layer
`misalignment_and_patch_maps.md` §8 asks for, and remains future work. The
survey channel's `s` is one-dimensional by design.

## 2. What slips and what does not

Convention #3 tracks `(z, δ)` with `z` a **path deficit**: `z = s - ℓ`, the
design arc minus the particle's own path length. Two facts follow, and the
distinction between them is the entire content of F16:

1. **The path deficit does not slip with velocity.** An off-momentum
   particle in a dispersion-free straight section moves slower but along the
   same path: `ℓ` advances with `s` and `z` is constant. This is why the
   convention-#3 lattice maps carry no velocity term *by construction* —
   Octopus's exact drift changes `z` only through transverse path
   lengthening, zero on axis — and why they are correct to do so.
2. **The arrival time slips, without bound.** Against the reference clock,
   the same particle arrives later by `Δt = s·(1/β - 1/β₀)/c`, growing with
   every turn. The RF phase is a statement about arrival time, so this term
   is precisely what the cavity must see, and in a pure-#3 ring the cavity
   is the only element that can supply it.

So the slip factor splits: `α_c` (path lengthening through dispersion in
bends) lives in the lattice maps and arrives through `R₅₆`; `-1/γ₀²`
(velocity) lives in the time coordinate and must enter at the cavity. A ring
whose cavity reads `z/β` alone closes with `η = α_c` — the F16 defect,
measured as a 1.84× synchrotron tune error at 2.5 GeV proton with
`α_c = 0.2`.

## 3. The correct form: a symplectic z-shift

The cavity reconciles path and time once per pass: before its kick, it
advances the `z` its phase reads by the time slip accumulated since the
previous cavity kick,

```
z ← z + Δs · g(δ),      g(δ) = β/β₀ - 1,
```

with `Δs` the arc distance from the previous cavity's kick, wrapping the
turn (`Σ Δs = C`; one cavity: `Δs = C`). Between kicks the lattice maps do
not touch `δ`, so per-segment shifts compose to exactly the per-turn
`C·(β/β₀ - 1)` whatever the cavity placement. The map `(z, δ) → (z + f(δ), δ)`
is symplectic for any `f`, and the kick that follows is the unchanged
conjugated body, so the composition is symplectic exactly.

Linearized, the shift contributes `d z/d δ = Δs·g'(0) = Δs/γ₀²` per turn —
`g'(0) = 1/γ₀²` because `dβ/β = (1/γ²)·dp/p` — with the sign *opposing* the
lattice `R₅₆`'s `α_c` term, closing the ring with the full
`η = α_c - 1/γ₀²` and the correct transition side.

**The exact, cancellation-free `g`.** With `p_t = ΔE/(P₀c)` and
`β/β₀ = (1+δ)/(1+β₀p_t)`, the literal `β/β₀ - 1` subtracts two numbers near
1 and loses all relative precision at large `γ₀`. The conjugate identity
`(1+δ)² - (1+β₀p_t)² = p_t(2/β₀ + p_t)/γ₀²` (the U14-4 family) gives

```
g(δ) = p_t (2/β₀ + p_t) / [ γ₀² (2 + δ + β₀p_t) (1 + β₀p_t) ]
```

— the `1/γ₀²` smallness explicit, every factor well-conditioned, valid at
any energy and amplitude. This is `_velocity_slip_g` in `rf_cavity.jl`,
pinned against BigFloat in the suite.

**The injection convention.** The shift fires on every pass including the
first, so the injection pass is treated as one full wrap when its true
accumulated arc is only `s_cavity`. This misdates the first slip by one
partial turn — a bounded, `δ`-dependent redefinition of the injection
reference time, far below anything the dynamics can see (the per-turn slip
itself is `~C·δ/γ₀²`), and it buys the property that the correction is a
per-op *constant*: no turn counter, no context requirement, identical on the
fused, contextless, and direct `track_particle` paths.

## 4. The two wrong forms, kept with their evidence

Both were plausible enough to design around; one was briefly implemented.
The probe that killed them is the record
(`nu_s` measured on a `Drift(C) + Linear6D(R₅₆) + cavity` ring at 2.5 GeV
proton, `α_c = 0.2`, `C = 100 m`, prediction `ν_s(full η) = 0.0021744`):

- **Constant `s = Δs` inside the coordinate conversion** (passing the arc to
  `convert_longitudinal`'s `s` argument both ways). Measured
  `ν_s = 0.004028` — the `α_c`-only value to 0.7%, i.e. **no correction at
  all**. Why: the conversion's `s`-terms enter and leave symmetrically, so a
  constant `s` cancels out of the one-turn map; the phase *value* contains
  `k·Δs·g(δ)` but its per-turn *increment* — the only thing a tune can see —
  is zero. The conversion's `s` exists to relabel a coordinate (`-ℓ` versus
  `s-ℓ`, the PTC `TIME=FALSE` offset trap), not to inject dynamics.
- **Accumulated `s = turn·C + s_elem` inside the conversion.** Supplies the
  right phase increment but at the price of `turn·C`-sized state: the
  back-conversion acquires secular coordinate jumps `∝ s·Δβ` that grow
  without bound, and the phase argument's conditioning degrades linearly in
  the turn number. Physically it is the `TOTALPATH` route — honest, but it
  makes a bounded tracked pair unbounded.

The z-shift form is the same physics as the second with the accumulation
telescoped into the state the maps already track: measured
`ν_s = 0.0021973`, agreeing with the full-`η` prediction to the probe's
crossing-count quantization (~1%), with `max|z|` over 4096 turns at
`1.0000233×10⁻³` from a `10⁻³` start — bounded, as it must be.

## 5. What the suite pins

- `ν_s` against the **full** `η` (the theory note's §8 item 4 criterion, at
  the 2.5 GeV / `α_c = 0.2` point where the defect was 1.84×);
- the transition side: at `α_c < 1/γ₀²` the corrected ring is unstable at
  the phase where the uncorrected one oscillates happily — an A/B against
  the bare-compiled cavity, which deliberately retains the `s = 0` boundary;
- `_velocity_slip_g` against BigFloat across energies and amplitudes;
- the survey walker against `s_positions` and (externally) against MAD-X
  `SURVEY` for nested, reflected, and curved fixtures;
- the two-cavity `Δs` partition and its wrap to `C`.
