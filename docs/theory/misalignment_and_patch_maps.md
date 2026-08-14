# Misalignments, Rotations, and the Patch Map

How a rigid displacement of a magnet becomes a tracking map, compared between
PTC (as distributed with MAD-X 5.03.06) and Bmad, with the design this implies
for Octopus.

Sources read, both under `Library/AcceleratorCodes/`:

| what | where |
|---|---|
| PTC misalignment driver | `madx-5.03.06/libs/ptc/src/Sm_tracking.f90:883` (`MIS_FIBR`) |
| PTC Euclidean primitives | `madx-5.03.06/libs/ptc/src/Sc_euclidean.f90` (`TRANSR`, `ROT_XYR`, `ROT_XZR`, `ROT_YZR`) |
| PTC misalignment setup | `madx-5.03.06/libs/ptc/src/Sl_family.f90:1049` (`MISALIGN_FIBRE`) |
| Bmad rotation convention | `bmad-ecosystem/bmad/geometry/floor_angles_to_w_mat.f90` |
| Bmad patch element | `bmad-ecosystem/bmad/low_level/track_a_patch.f90` |
| Bmad misalignment applier | `bmad-ecosystem/bmad/code/offset_particle.f90` |

Longitudinal sign convention throughout: Octopus tracks $z = s - \ell$, which is
the negative of PTC's `X(6)`. Every longitudinal formula quoted from PTC below
is written in PTC's sign; flip it on the way in, exactly as the existing lattice
maps do (see `lattice_hamiltonian_and_conventions.md` Section 2.1).

## 1. What a misalignment actually is

A magnet is a field in space. Misaligning it does not change the field; it
changes the relationship between the magnet's body frame and the design frame
the tracking coordinates live in. So the map is a **change of frame applied to
the particle**, not a change to the element's physics:

$$\text{lab} \xrightarrow{\;M_\text{in}\;} \text{body} \xrightarrow{\;\text{element}\;} \text{body} \xrightarrow{\;M_\text{out}\;} \text{lab}$$

This is the structure proposed for Octopus — `(error, entrance edge, body, exit
edge, error)` — and it is what both codes do. It has two properties worth
stating explicitly because they are what make the approach safe:

- **The element's own map is untouched.** Fringes, integrator, and field
  expansion all continue to run in body coordinates, so nothing already
  validated against PTC has to be revisited.
- **Symplecticity is inherited.** Each $M$ is a canonical transformation, so
  $M_\text{out} \circ E \circ M_\text{in}$ is symplectic whenever $E$ is. No new
  symplecticity argument is needed.

The subtlety is entirely in what $M_\text{out}$ is, and Section 5 is where the
two codes genuinely differ.

## 2. The frame transformation

A rigid displacement is an element of the Euclidean group: a rotation $W$ and a
translation $\vec{d}$. Acting on a particle, both the position and the momentum
direction transform, and then the particle must be **carried back onto the new
transverse plane**, because tracking coordinates are defined on a plane of
constant $s$ and the displaced plane is a different one.

That last step is what makes these maps nontrivial. A misalignment is not a
matrix multiply; it is a matrix multiply *plus an exact drift onto a tilted
plane*, and the drift distance depends on the particle. Both codes get this
right; they factor it differently.

Writing $\vec{p} = (p_x, p_y, p_s)$ with

$$p_s = \sqrt{(1+\delta)^2 - p_x^2 - p_y^2},$$

the transformation is

$$\vec{r}' = W(\vec{r} - \vec{d}), \qquad \vec{p}' = W\vec{p},$$

followed by a drift of $-r'_3$ along the new direction.

## 3. PTC: four exact one-parameter maps

PTC never forms $W$. It applies the Euclidean group as a product of exact
one-parameter maps, each of which does its own drift-back. From `MIS_FIBR`:

```fortran
IF(ENTERING) THEN
   CALL ROT_YZ(C%CHART%ANG_IN(1),X,...)   ! about x  (y pitch)
   CALL ROT_XZ(C%CHART%ANG_IN(2),X,...)   ! about y  (x pitch)
   CALL ROT_XY(C%CHART%ANG_IN(3),X)       ! about s  (roll)
   CALL TRANS(C%CHART%D_IN,X,...)         ! translation
ELSE
   ... same with ANG_OUT, D_OUT
```

so the order is **rotate about $x$, then $y$, then $s$, then translate**.

### 3.1 The primitives

**`ROT_XY(A)`** — roll about the longitudinal axis. The only one needing no
drift, because it maps the transverse plane to itself:

$$\begin{pmatrix} x'\\ y'\end{pmatrix} = \begin{pmatrix} \cos A & \sin A\\ -\sin A & \cos A\end{pmatrix}\begin{pmatrix} x\\ y\end{pmatrix},$$

and identically on $(p_x, p_y)$. This is the *passive* rotation by $+A$.

**`ROT_XZ(A)`** — pitch about the $y$ axis. With $p_s$ as above,

$$P_T = 1 - \frac{p_x \tan A}{p_s}, \qquad s^\star = \frac{x \tan A}{P_T},$$
$$x' = \frac{x}{\cos A\, P_T},\quad p_x' = p_x \cos A + p_s \sin A,\quad y' = y + \frac{p_y s^\star}{p_s},\quad T' = T + \frac{(1+\delta)s^\star}{p_s}.$$

$s^\star$ is the signed distance the particle must be drifted to land on the
rotated plane. Octopus already has this map as `_rot_xz`, where it is used for
the pole face; it is bit-identical to PTC's and is already validated to 5e-13 by
the `sbend_edge` reference case.

**`ROT_YZ(A)`** — pitch about the $x$ axis. PTC implements it by relabelling
rather than deriving it again:

```fortran
XN(1)=X(3); XN(2)=X(4); XN(3)=X(1); XN(4)=X(2)   ! swap x <-> y
CALL ROT_XZ(A,XN,...)
```

i.e. $\mathrm{ROT\_YZ}(A) = S \circ \mathrm{ROT\_XZ}(A) \circ S$ with $S$ the
$x \leftrightarrow y$ swap. Worth copying: it is one line, and it cannot drift
out of agreement with the $x$-$z$ version.

**`TRANS(\vec{d})`** — transverse shift plus an exact drift by $d_3$:

$$x' = x - d_1 + \frac{d_3 p_x}{p_s}, \qquad y' = y - d_2 + \frac{d_3 p_y}{p_s}, \qquad T' = T + \frac{d_3 (1+\delta)}{p_s}.$$

### 3.2 Where the numbers come from

`MISALIGN_FIBRE` does not store the user's offsets. It stores the transformation
between the **surveyed ideal frames and the actual frames**:

```fortran
CALL COMPUTE_ENTRANCE_ANGLE(F0%ENT, F%ENT, S2%CHART%ANG_IN)
CALL COMPUTE_ENTRANCE_ANGLE(F%EXI, F0%EXI, S2%CHART%ANG_OUT)
D_IN  = F%A  - F0%A
D_OUT = F0%B - F%B
CALL CHANGE_BASIS(D_IN,  GLOBAL_FRAME, S2%CHART%D_IN,  F%ENT)
CALL CHANGE_BASIS(D_OUT, GLOBAL_FRAME, S2%CHART%D_OUT, F0%EXI)
```

Note the reversed argument order for the exit (`F%EXI, F0%EXI` against
`F0%ENT, F%ENT`) and the different basis. **The entry and exit patches are
computed independently from geometry, and are not assumed to be inverses.**
This is the single most important design fact in this note, and Section 5
explains why it matters.

## 4. Bmad: one rotation matrix, one drift

Bmad forms $W$ explicitly. From `floor_angles_to_w_mat(theta, phi, psi)`, with
`theta = x_pitch`, `phi = y_pitch`, `psi = tilt`:

$$W = R_y(\theta)\, R_x(-\phi)\, R_z(\psi),$$

which the source writes out entry by entry, together with its transpose as
`w_mat_inv`. The forward direction uses the inverse.

`track_a_patch` is then the whole Euclidean map in one place:

```fortran
r_vec = [orbit%vec(1) - v(x_offset$), orbit%vec(3) - v(y_offset$), -v(z_offset$)]
call floor_angles_to_w_mat (v(x_pitch$), v(y_pitch$), v(tilt$), w_mat_inv = ww)
p_vec = matmul(ww, p_vec)
r_vec = matmul(ww, r_vec)
...
orbit%vec(1) = orbit%vec(1) - r_vec(3) * p_vec(1) / p_vec(3)
orbit%vec(3) = orbit%vec(3) - r_vec(3) * p_vec(2) / p_vec(3)
orbit%vec(5) = orbit%vec(5) + r_vec(3) * rel_p / p_vec(3) + ...
```

Translate, rotate both 3-vectors, then a single exact drift by $-r_3$. This is
the same map as PTC's four-fold product, factored once instead of four times,
and it is cheaper: one square root and one drift rather than three drifts.

`offset_particle` applies the same machinery to ordinary elements, with one
structural difference that matters:

```fortran
position%r = position%r - [x_off, y_off, z_off + ele%orientation*ds_center]
call floor_angles_to_w_mat (xp, yp, 0.0_rp, w_mat_inv = ws)
position%r = matmul(ws, position%r)
position%w = matmul(ws, position%w)
position%r(3) = position%r(3) + L_half
```

**Bmad references the displacement to the element centre**, not to its entrance:
it shifts to the centre, rotates there, and shifts back by $L/2$. This is the
physically natural choice — "the magnet is rotated about its own centre by
`x_pitch`" is what a survey report means — and it is *not* what you get by
applying a pitch at the entrance face.

## 5. The bend, and why the exit patch is not the inverse of the entry patch

For a **straight** element, if the entry patch is $M$, the exit patch is
$M^{-1}$ conjugated by the drift along the body. Nothing surprising.

For a **bend** this fails, because the body rotates the reference frame by the
bend angle $\theta$. The design frame at the exit is not parallel to the design
frame at the entrance. A rigid displacement of the magnet therefore looks
different from the two ends: a pure $x$-offset at the entrance is a mixture of
$x$-offset and $z$-offset at the exit, rotated by $\theta$.

The two codes solve this in opposite directions:

- **PTC** never has the problem, because it never derives the exit patch from
  the entry patch. `MISALIGN_FIBRE` computes `ANG_OUT`/`D_OUT` from the surveyed
  exit frames directly, so the bend angle is already baked into the geometry.
  The cost is that the misalignment must be expressed as a frame pair, and a
  survey is needed to build it.
- **Bmad** derives the exit condition from the misalignment parameters, so it
  must transport along the arc explicitly. That is what `bend_shift` is for, and
  why `offset_particle` has a separate `sbend$` branch:

  ```fortran
  position = bend_shift(position, ele%value(g$), ele%orientation*ds_center, ref_tilt = ref_tilt)
  call ele_misalignment_L_S_calc(ele, L_mis, ws)
  ...
  if (ref_tilt /= 0) then
     position = bend_shift(position, ele%value(g$), -L_half, ref_tilt = ref_tilt)
     ...
  ```

  with a further `ref_tilt` conjugation, because rolling a bend about the design
  axis is not the same as rolling a straight magnet.

**Consequence for Octopus.** The proposed `(error, entrance edge, body, exit
edge, error)` composition is right, but the two `error` maps must be *computed
independently*, not related by inversion. Getting this wrong is invisible on a
straight magnet and wrong at first order on every bend in the ring — the worst
possible failure mode, since a FODO test would pass.

## 6. Comparison

| | PTC | Bmad |
|---|---|---|
| representation | product of four exact 1-parameter maps | one $3\times3$ $W$ plus one drift |
| rotation order | $x$ pitch, $y$ pitch, roll, translate | $W = R_y(\theta)R_x(-\phi)R_z(\psi)$ |
| reference point | surveyed frames (entry and exit stored separately) | element centre |
| bend handling | implicit — geometry already carries the angle | explicit `bend_shift` + `ref_tilt` conjugation |
| drifts onto plane | three (one per rotation) plus one in `TRANS` | one |
| input | frame pair from a survey | offsets and pitches as element attributes |
| exactness | exact | exact |

Both are exact and symplectic. They are the same map, factored differently.

## 6a. The reference point: MAD-X and Bmad disagree (measured)

Section 4 noted that Bmad references a misalignment to the element **centre**.
MAD-X does not. `MAD_MISALIGN_FIBRE` (`Sl_family.f90:1051`), which is what
`ptc_align` calls to transfer an `EALIGN` error into PTC, ends with

```fortran
ENT = S2%CHART%F%ent      ! the fibre's ENTRANCE basis
T   = S2%CHART%F%A        ! the fibre's ENTRANCE point
call MISALIGN_SIAMESE(S2, MIS, T, ENT)
```

so the displacement is referenced to the **entrance frame**, with the offset
components taken in entrance axes. The angle mapping in the same routine is

```fortran
MAD_ANGLE(1) = -S1(4)     ! -DPHI     about x, applied second
MAD_ANGLE(2) = -S1(5)     ! -DTHETA   about y, applied third
MAD_ANGLE(3) =  S1(6)     !  DPSI     about s, applied first
```

The two conventions agree for a pure translation of a straight element and
disagree for everything else — including a *translation* of a bend, whose centre
axes are turned by $hL/2$ from its entrance axes. Octopus therefore exposes
`misalign_convention`, defaulting to `:bmad` (centre-referenced, and what survey
data means) with `:madx` available to reproduce MAD-X. (This paragraph and the
table caption below named the values `:center` and `:entrance` until the
2026-08-05_b audit; the constructor accepts only `:bmad` and `:madx`, so the
note's own reproduction instructions raised an `ArgumentError`. §6a below
already used the correct names, so the note contradicted itself.)

Measured against `EALIGN` + `ptc_align`, with `misalign_convention = :madx`,
one degree of freedom at a time on a quadrupole:

| MAD-X | Octopus | agreement |
|---|---|---|
| `DX`, `DY`, `DS` | `x_offset`, `y_offset`, `z_offset` | 4.1e-13, 4.1e-13, 4.4e-13 |
| `DTHETA` | `x_pitch` | 4.9e-13 |
| `DPHI` | `y_pitch` | 4.8e-13 |
| `DPSI` | `tilt` | 5.0e-13 |

all at the reference table's print-precision floor. These are committed as the
`quad_mis_*` and `sext_mis_*` cases.

### The rotation composition order

A single rotation cannot distinguish the two codes, so the table above pins the
keyword mapping and nothing more. Setting all six at once initially disagreed at
2.7e-6 — second order in the angles. The cause is in `GEO_ROTB`
(`Sd_frame.f90:629`), which builds

```
basis^-1 · R_z(ANG(3)) · R_y(ANG(2)) · R_x(ANG(1)) · basis
```

and in how `MAD_MISALIGN_FIBRE` calls it: three times, with `ent1 = ent2 = ent`
reset before each, so each rotation is taken about the **already rotated** axes.
That is an intrinsic sequence $z$, then $x$, then $y$, which composes as

$$W_\text{MAD-X} = R_z(\psi)\,R_x(-\phi)\,R_y(\theta),$$

the reverse of Bmad's fixed-axis

$$W_\text{Bmad} = R_y(\theta)\,R_x(-\phi)\,R_z(\psi).$$

The elementary rotations and their signs are the same; only the order differs.
The two therefore agree exactly for any single rotation and differ at second
order once two are nonzero. Octopus implements both, selected by
`misalign_convention` (`:bmad` default, `:madx`), which also carries the
reference point — the two halves of a convention are not independently
meaningful. With `:madx` the all-six case agrees to **4.96e-13**.

### Bends

Misaligned bends agree with `EALIGN` to **4.5e-13**, both for a pure translation
and for all six degrees of freedom, using the survey of Section 5. The survey
sign is independently confirmed against MAD-X's own `SURVEY`, which gives
$X_\text{exit} = -\rho(1-\cos\theta) = -0.108545$ for `angle=0.198, l=1.1`,
matching the $-(1-\cos hs)/h$ used here.

One trap, recorded because it cost a debugging cycle and looked exactly like a
geometry error: a misaligned-bend comparison must also set
`bend_model = :drift_kick`, since PTC runs `MODEL=1`. Comparing an
exact-splitting bend against PTC's drift-kick one produces an O(1e-3) residual
that has nothing to do with the misalignment, and which scales with the bend
angle in a way that mimics a wrong exit patch.

### Which frame the error is quoted in, when the design orbit is rolled

A third convention split hides behind the same `misalign_convention` switch, and
it appears only once a bend carries a `ref_tilt` (Section 6b) *and* a
misalignment. Both codes displace the same magnet — the rolled one. They differ
over the axes the displacement and pitches are **measured along**:

| | frame the `EALIGN`/offset vector lives in | source |
|---|---|---|
| Bmad | the **rolled** frame — the element's own axes, which `ref_tilt` has turned | `track_a_bend` rotates by `ref_tilt`, then calls `offset_particle` inside it |
| MAD-X | the **unrolled** design frame — `dx` stays horizontal whatever the roll | `EALIGN` is survey data about the machine |

Octopus keeps `ref_tilt` as the outer map in both and resolves the split by
conjugating the rigid transform for `:madx`:

$$W \mapsto R_z(-\psi)\,W\,R_z(\psi), \qquad d \mapsto R_z(-\psi)\,d .$$

Measured, at `ref_tilt = 0.3` on a combined-function bend:

| model | `dx` only | all six |
|---|---|---|
| error quoted in the rolled frame | 2.0e-4 | 3.5e-4 |
| error quoted in the unrolled frame (`:madx`) | **2.8e-13** | **4.5e-13** |

Both parts of the transform must move together: rotating the offset but leaving
$W$ alone still leaves 1.2e-4 on the all-six case.

This overturned the prediction recorded in `docs/todo.md`, which reasoned that a
design choice must compose outside an error and concluded the roll wraps the
misalignment in every convention. That is true of the *maps* and false of the
*frame the error is stated in*, which is the thing the comparison actually
measures. The prediction about the trap was right: at one nonzero parameter every
model above agrees, so none of the one-at-a-time cases that pin the rest of this
note could have caught it.

## 6b. `ref_tilt`: rolling the design orbit

`ref_tilt` rolls the design orbit plane; `tilt` rolls the magnet body. The first
is geometry the lattice designer chose, the second is an error. MAD-X spells the
first as the bend's own `tilt=` keyword and the second through `EALIGN, dpsi`,
so **MAD-X's bend `tilt` is Bmad's `ref_tilt`, not Octopus's `tilt`** — the same
word for both meanings, which is the trap.

The map is a conjugation,

$$M_\text{rolled} = R(\psi) \, M \, R(-\psi),$$

with $R$ rotating $(x,p_x)$ against $(y,p_y)$. It is complete for tracking, and
that is worth stating because an earlier draft of this note said otherwise. A
roll about $s$ maps the $s=0$ plane to itself, so unlike a misalignment there is
no drift onto a displaced face and no path-length term; $z$ and $p_z$ pass
through untouched. Octopus's lattice is a sequence of maps in local curvilinear
frames, a bend already turns its frame by $hL$, and conjugating it makes the
frame turn in a rolled plane — after which the next element simply receives
coordinates in the new frame. Nothing absolute is needed. A vertical bend is
$\psi = \pi/2$.

What the conjugation does *not* give is where the magnet sits in the building.
Reporting that is a survey question and still needs the geometry layer Section 8
asks for; tracking through it does not.

Agreement with PTC, driven through `sbend, tilt=`: **3.5e-13** for a pure dipole,
**4.1e-13** at $\psi=\pi/2$, **4.6e-13** for a combined-function bend.

## 7. Recommended design for Octopus

1. **Take Bmad's factorization, PTC's bookkeeping.** Form $W$ once and apply a
   single exact drift — cheaper, one code path, and it keeps the GPU kernel free
   of three nested square roots. But store the entry and exit transforms
   *separately*, as PTC does, rather than deriving one from the other.

2. **Reference to the element centre**, following Bmad, because that is what
   alignment data means. For a straight element of length $L$ this makes the
   entry transform $T(-L/2)\,W\,T(+L/2)$ in the obvious notation; for a bend the
   $T$'s become arc shifts.

3. **Reuse `_rot_xz`.** It is already in `lattice_magnets.jl`, already matches
   PTC bit for bit, and is already validated by `sbend_edge`. `ROT_YZ` should be
   the $x \leftrightarrow y$ relabelling of it, exactly as PTC does, so the two
   cannot drift apart.

4. **Keep the misalignment out of `ElementSpec`'s physics fields.** A
   misalignment is not a property of the magnet's field; it belongs with the
   element's placement. This matters for the two-layer design: `compile_runtime`
   should fold the transforms into the runtime object, so a magnet with no
   misalignment compiles to exactly the code it has today.

5. **A `patch` element is worth having on its own**, independent of
   misalignments — it is how you express a deliberate geometric transition
   (a crossing angle, a beamline junction, a spectrometer arm). Bmad's
   `track_a_patch` is a complete specification and needs no misalignment
   machinery.

6. **Validation.** A rigid displacement applied to a whole *line* must cancel:
   misaligning every element of a cell by the same transform, then applying the
   inverse patch at both ends, must reproduce the aligned map to round-off. That
   is a contract that needs no external reference and would catch a wrong exit
   patch immediately. Against PTC, `ptc_align` supplies the reference case.

## 8. Open questions

- ~~**Sign and order conventions must be pinned against a reference case before
  the maps are trusted.**~~ **Done**: both compositions are implemented and
  selected by `misalign_convention`, and the `:madx` branch is pinned by
  `quad_mis_all` and `cfbend_mis_all` at 4.96e-13 (Section 6a). The warning that
  the difference is second order — too small for a symplecticity test to see,
  large enough to matter at $10^{-4}$ rad — held, and is why those cases set all
  six degrees of freedom at once.
- ~~**`ref_tilt` versus `tilt`.**~~ **Done as of 2026-08-02**: Section 6b. The
  concern that it should be settled *before* bends get misalignments rather than
  after turned out to be well placed but not blocking — the two interact, and
  resolving the interaction late meant it was resolved by measurement rather
  than by assumption. The assumption on record was wrong (Section 6a, last
  subsection).
- ~~**Aperture.** Octopus has no aperture model at all.~~ **Stale as of
  2026-08-01**: `ApertureSpec` exists, with per-particle loss records
  ([`aperture_and_particle_loss.md`](aperture_and_particle_loss.md)). The point
  that a misaligned magnet is the main reason a particle hits an aperture still
  stands, and the aperture deliberately carries its own `dx`/`dy` rather than
  routing through the misalignment frames — see that note's Section 4.
- ~~**Survey.** PTC's approach presumes a survey exists. Octopus has no geometry
  layer, so the centre-referenced parameterization is the only workable one for
  now; a survey would be needed for a machine described by measured frames.~~
  **Done (2026-08-14)**: the floor-plan survey —
  [`floor_plan_survey.md`](floor_plan_survey.md), `survey(line)` in
  `src/elements/floor_plan.jl` — propagates the global frame per element
  through the same `_patch_rotation` primitives this note pinned, and is
  checked element-for-element against MAD-X `SURVEY` (all six floor columns,
  worst deviation 7.1e-15 over nine fixtures) by the
  `MADXSurveyConsistencyContract`. The centre-referenced misalignment
  parameterization stays; the survey deliberately excludes misalignments and
  `tilt`, which are errors about the frame it computes.
