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
`misalign_reference`, defaulting to `:center` (Bmad, and what survey data means)
with `:entrance` available to reproduce MAD-X.

Measured against `EALIGN` + `ptc_align`, with `misalign_reference = :entrance`,
one degree of freedom at a time on a quadrupole:

| MAD-X | Octopus | agreement |
|---|---|---|
| `DX`, `DY`, `DS` | `x_offset`, `y_offset`, `z_offset` | 4.1e-13, 4.1e-13, 4.4e-13 |
| `DTHETA` | `x_pitch` | 4.9e-13 |
| `DPHI` | `y_pitch` | 4.8e-13 |
| `DPSI` | `tilt` | 5.0e-13 |

all at the reference table's print-precision floor. These are committed as the
`quad_mis_*` and `sext_mis_*` cases.

**Unresolved: composing several rotations.** With all six degrees of freedom set
at once the agreement degrades to 2.7e-6 — second order in the angles, and far
above the floor. Each rotation is individually correct, so the discrepancy is in
the order the three are composed: MAD-X rotates the frame by `DPSI`, then
`DPHI`, then `DTHETA`, and if those `GEO_ROT` calls compose in the opposite
matrix order to Bmad's $W = R_y R_x R_z$ the two agree at first order and differ
at second. This has not been settled, so no multi-rotation case is committed —
a tuned one would only hide it.

**Also unresolved: the bend.** A misaligned bend is implemented through the
survey of Section 5 and is internally consistent — symplectic to 1e-15, exactly
the identity at zero misalignment, and correct under a rigid displacement of a
whole line — but it does **not** yet reproduce `EALIGN` on a bend. The survey
sign convention itself is confirmed against MAD-X's own `SURVEY`, which gives
$X_\text{exit} = -\rho(1-\cos\theta) = -0.108545$ for `angle=0.198, l=1.1`,
matching the $-(1-\cos hs)/h$ used here. The remaining disagreement is most
likely the same rotation-composition question, since MAD-X's bend misalignment
routes through the same `MAD_MISALIGN_FIBRE`.

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

- **Sign and order conventions must be pinned against a reference case before
  the maps are trusted.** PTC's order is $x$-pitch, $y$-pitch, roll; Bmad's $W$
  is $R_y R_x R_z$ with a sign flip on $\phi$. These are not obviously the same
  composition, and the difference is second order in the angles — small enough
  to hide in a symplecticity test and large enough to matter at $10^{-4}$ rad.
- **`ref_tilt` versus `tilt`.** Bmad distinguishes rolling the *design orbit* of
  a bend from rolling the *magnet*. Octopus has neither yet, and the distinction
  only exists for bends. It needs to be settled before bends get misalignments,
  not after.
- **Aperture.** A misaligned magnet is the main reason a particle hits one, and
  Octopus has no aperture model at all. The two features are worth designing
  together.
- **Survey.** PTC's approach presumes a survey exists. Octopus has no geometry
  layer, so the centre-referenced parameterization is the only workable one for
  now; a survey would be needed for a machine described by measured frames.
