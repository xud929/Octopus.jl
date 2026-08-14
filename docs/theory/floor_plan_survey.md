# The Floor-Plan Survey

> **Status: derivation (2026-08-14), written BEFORE the implementation, per
> owner direction.** This note derives the global-geometry survey — position
> `(X, Y, Z)` and orientation `(θ, φ, ψ)` per element, MAD-X's `SURVEY` — that
> [`arc_survey_and_velocity_slip.md`](arc_survey_and_velocity_slip.md) §1
> deliberately does not compute and
> [`misalignment_and_patch_maps.md`](misalignment_and_patch_maps.md) §8 asks
> for. Every convention below is **measured against MAD-X 5.03.06**, not
> assumed; the probe numbers are reproduced in the tables and re-checked by
> the extended `MADXSurveyConsistencyContract` once implemented.

## 1. Frame state and its propagation

The survey propagates a reference frame down the line:

- `V ∈ ℝ³`: the global position of the local origin;
- `W ∈ SO(3)`: the rotation taking local axes `(x̂, ŷ, ŝ)` to global
  `(X, Y, Z)` — `W`'s columns are the local axes expressed globally.

Initial frame: `V = 0`, `W = I` — local `ŝ` along global `+Z`, `x̂` along
`+X`, `ŷ` along `+Y` (measured: a bare drift advances `Z` only).

Each element contributes a **local** displacement `d` and rotation `R`:

```
V ← V + W·d,        W ← W·R.
```

Composition is associative and per-element local, so nesting, repetition and
reflection need no special handling beyond the line expansion the arc survey
already validates against MAD-X.

## 2. Per-element geometric maps

With `R_X, R_Y, R_Z` right-handed rotations about the LOCAL axes:

| element | `d` (local) | `R` |
|---|---|---|
| straight of length `L` (drift, quad, sext, oct, multipole, solenoid, cavities, thick anything) | `(0, 0, L)` | `I` |
| sbend, angle `α`, arc `L`, `ρ = L/α`, design roll `t` (`ref_tilt`) | `R_S(t)·(ρ(cos α − 1), 0, ρ sin α)` | `R_S(t)·R_Y(−α)·R_S(−t)` |
| thin element (`L = 0`) | `0` | `I` |
| patch | its `(dx, dy, dz)` and rotations, in `patch.jl`'s exact map order (§4) | per patch |

`R_S` is the rotation about local `ŝ` (= local `R_Z`). Two measured sign
anchors pin the bend row (probe `floorplan.madx`, MAD-X 5.03.06, full-double
TFS):

- `sbend, l=2, angle=0.5` alone: exit `X = 4(cos 0.5 − 1) = −0.489669…`,
  `Z = 4 sin 0.5 = 1.917702…`, `θ = −0.5` exactly. **Positive bend angle
  displaces toward −X and decreases θ.**
- the same bend with `tilt = π/2`: displacement moves to
  `Y = −0.489669…` (downward), `φ = −0.5`, `ψ ≈ 0` — the roll conjugation
  `R_S(t)·(…)` reproduces both, and the surveyed angles absorb the roll into
  `(θ, φ)` with no residual `ψ`, exactly as the conjugated `R` predicts.

**Misalignments do not move the survey.** `x_offset`/`tilt`/… are errors
*about* the design frame (the survey IS the design frame), matching MAD-X,
whose `EALIGN` leaves `SURVEY` untouched. `ref_tilt` is design and does.

**The patch caveat inverts here.** The arc survey documents that a patch's
`dz` does not advance `s`; the floor plan is the opposite — patches are
*pure geometry* and contribute exactly their frame maps. The two surveys
answer different questions and the difference is deliberate on both sides.

## 3. The MAD-X angle triple, measured

MAD-X reports orientation as `(θ, φ, ψ)` with

```
W = R_Y(θ) · R_X(−φ) · R_Z(ψ)
```

acting so that the local beam direction is

```
ŝ = W·(0,0,1) = (cos φ sin θ,  sin φ,  cos φ cos θ).
```

Measured anchors (each a one-element probe plus a 3 m drift):

| probe | θ | φ | ψ |
|---|---|---|---|
| `sbend, angle=0.5` | `−0.5` | `0` | `0` |
| `sbend, angle=0.5, tilt=π/2` | `−3.3e-17` | `−0.5` | `−8.5e-18` |
| `sbend, angle=0.5, tilt=0.3` | `−0.4810158447` | `−0.1421582627` | `−0.0349203257` |
| `srotation, angle=0.2` | `0` | `0` | `+0.2` |
| `yrotation, angle=0.1` | `−0.1` | `0` | `0` |

and the drift displacements confirm `ŝ` above to full double precision
(`ΔX = 3 cos φ sin θ`, `ΔY = 3 sin φ`, `ΔZ = 3 cos φ cos θ` in every case).
The `tilt = 0.3` row is the load-bearing one: it fixes the *extraction*

```
θ = atan2(W₁₃, W₃₃),   φ = asin(W₂₃),   ψ = atan2(W₂₁, W₂₂),
```

whose values for `W = R_S(0.3)·R_Y(−0.5)·R_S(−0.3)` must reproduce the
measured triple — the implementation asserts exactly this before anything
else, and the extended contract then pins it per element against MAD-X.

**The gimbal edge.** At `φ = ±π/2` (`ŝ` along `±Y`, a vertical shot) `θ` and
`ψ` are individually undefined; only `θ ∓ ψ`-type combinations survive.
MAD-X prints *some* pair there; the implementation must not fail on the
edge, and the contract deliberately avoids fixtures at exactly `±π/2`
elevation while the pure-vertical probe above (`tilt = π/2` bend, ending at
`φ = −0.5`) covers the approach to it.

**Elevation sign.** `φ > 0` is upward (`ŝ_Y = sin φ`), so the `tilt = +π/2`
positive-angle bend — which displaces downward — exits at `φ < 0`. The
`asin` form keeps `φ ∈ [−π/2, π/2]`, which is the range MAD-X uses.

## 4. What the implementation must pin before it is trusted

1. The `tilt = 0.3` extraction identity above, in isolation.
2. `srotation`/`yrotation` sign mapping onto the patch primitives:
   MAD-X `SROT(+a)` is `W ← W·R_Z(+a)` (measured `ψ = +0.2`), `YROT(+a)` is
   `W ← W·R_Y(−a)` (measured `θ = −0.1`). Octopus's patch rotation
   parameters must be mapped by MEASUREMENT against `patch.jl`'s tracking
   maps — the patch's geometric map and its coordinate map must be the same
   transformation read two ways, or a patched line's survey and its
   tracked orbit silently disagree (the worst failure mode of Section 5 of
   the misalignment note).

   **Measured at implementation (2026-08-14).** The frame applies the
   TRANSPOSE of `_patch_rotation` (coordinates and frames transform
   contragradiently), and with that one choice: `angle_y = +0.1` matches
   `YROT(+0.1)` exactly (`θ = −0.1`, same drift displacement to the last
   digit), while `angle_s = +0.2` gives `ψ = −0.2` — the **opposite roll
   sense** from `SROT(+0.2)`. That is not a survey error but the recorded
   U16-5 convention (`angle_s` and MAD-X's `tilt`/`psi` sense are
   inverses), now visible in a second observable; the contract fixture
   therefore twins `angle_s = +a` with `srotation, angle = −a`, and the
   vertical-bend fixture confirms `ref_tilt`'s sign IS MAD-X's `tilt`
   (`ref_tilt = +π/2` reproduces `tilt = +π/2` to the roundoff signature).
3. Ring closure: the `nested_reflected` fixture plus enough bend angle to
   close 2π must return to `V = 0`, `θ = −2π` (or its `atan2` branch),
   within roundoff — the global integration test no per-element comparison
   supplies.
4. Every fixture of the arc-survey contract, extended to all six floor
   columns, at full TFS precision.

## 5. Relation to the other geometry machinery

The survey composes the SAME rotation primitives `_frame_change` already
implements for misalignment conjugation (the 9-tuple `q` is a flattened
`W`), but it composes them *forward along the line* rather than
entry/exit-conjugated around one element. Reusing those primitives keeps one
rotation convention in the codebase; the survey adds only the frame
*accumulation* and the MAD-X angle extraction.

The arc survey (`s`) remains the tracking-side quantity — the velocity-slip
channel and `ds_turn` consume it — and the floor plan does not replace it:
`s` is intrinsic (unchanged by `ref_tilt`), the floor plan is extrinsic.
Both are computed, never stored, from the same `line_entries` walk.
