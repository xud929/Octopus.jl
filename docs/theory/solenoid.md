# The Solenoid: Exact Map, Canonical Momenta, and the Hard Edge

Derivation note for the solenoid element. Written before the implementation,
because the solenoid is the first Octopus element whose **stored momenta stop
being the physical transverse momenta inside the magnet**, and that single fact
decides the interface, the fringe model, and what a diagnostic is allowed to
read.

Builds on
[Lattice Hamiltonian, Multipole Strengths, and Longitudinal Conventions](lattice_hamiltonian_and_conventions.md),
which fixes the Hamiltonian, the normalization $\hat a = q\mathbf A/P_0$, and the
longitudinal convention. Nothing here restates those; this note only supplies
$\hat a$ for a solenoid and integrates the result.

## 1. Why the solenoid is different

Every element Octopus has today is either a drift ($\hat a=0$) or a kick whose
vector potential is purely longitudinal ($\hat a_s\neq0$, $\hat a_x=\hat a_y=0$).
In both cases the **transverse** canonical momenta equal the transverse kinetic
momenta everywhere, so `px`/`py` mean the same thing inside a magnet as outside
it, and no one has had to think about the difference.

A solenoid breaks that. Its field is longitudinal, so its vector potential is
**transverse**, and inside the magnet

$$
    p_x=\frac{P_x}{P_0}+\hat a_x,\qquad p_y=\frac{P_y}{P_0}+\hat a_y,
    \qquad \hat a_{x,y}\neq0 ,
$$

where $P_{x,y}$ are the physical (kinetic) momenta. The stored coordinates are
canonical — that is what makes the map symplectic and what the Hamiltonian is
written in — so **inside a solenoid `px` is not the particle's transverse
momentum.** Outside, $\hat a=0$ and the two coincide again.

Three consequences, all of which this note has to settle:

1. The entrance and exit "fringe kicks" of the textbook solenoid are **not a
   separate physical model**. They are the canonical$\leftrightarrow$kinetic
   conversion, forced by $\hat a$ jumping at a hard edge (Section 5).
2. Splitting a solenoid is not free: a split point lies *inside* the field,
   where the interface convention does not hold (Section 8).
3. A diagnostic that reads coordinates mid-solenoid reads canonical momenta and
   will mis-report emittance unless it converts (Section 8).

## 2. Field, potential, and the factor of two

Body field of an ideal solenoid, straight frame ($h=0$):

$$
    \mathbf B = B_s\,\mathbf e_s .
$$

Normalized strength, following the same $q/P_0$ convention as the multipoles:

$$
    k_s \;=\; \frac{qB_s}{P_0} \;=\; \frac{B_s}{B\rho} .
$$

This is MAD-X's `KS`. In the symmetric gauge,

$$
    \hat a_x=-\tfrac{1}{2}k_s\,y,\qquad
    \hat a_y=+\tfrac{1}{2}k_s\,x,\qquad
    \hat a_s=0 ,
$$

which reproduces the field:
$\hat b_s=\partial_x\hat a_y-\partial_y\hat a_x=\tfrac{1}{2}k_s+\tfrac{1}{2}k_s=k_s$. ✓

> **Trap — the factor of two.** Two different rotation rates live in this
> problem and both are called "the solenoid strength" in the literature. The
> **momentum** rotates at $k_s/p_s$; the **trajectory** advances along a
> direction rotated by half of that, $k_s/(2p_s)$ — the Larmor rate. The
> potential carries $k_s/2$, the momentum equation carries $k_s$. Section 4.3
> shows the half-angle falling out of the closed form, which is the check that
> catches a factor of two before it reaches a lattice.

Write $k\equiv k_s/2$ throughout, so $\hat a_x=-ky$, $\hat a_y=+kx$.

## 3. The Hamiltonian

Straight frame, no electric field, Octopus's longitudinal convention #3
($z=s-\ell$, $p_z=\delta$), from the conventions note:

$$
    H \;=\; \delta \;-\; \sqrt{(1+\delta)^2-(p_x-\hat a_x)^2-(p_y-\hat a_y)^2}
      \;=\; \delta - p_s ,
$$

with $\hat a_s=0$ contributing nothing. Define the **kinetic** transverse
momenta

$$
    P_x \;\equiv\; p_x-\hat a_x \;=\; p_x+k\,y ,\qquad
    P_y \;\equiv\; p_y-\hat a_y \;=\; p_y-k\,x ,
$$

and the longitudinal kinetic momentum

$$
    p_s \;=\; \sqrt{(1+\delta)^2-P_x^2-P_y^2} .
$$

## 4. Exact integration

### 4.1 $p_s$ is conserved

A static magnetic field does no work, so $|\mathbf P|$ is constant, and $\delta$
is constant because $H$ has no $z$ dependence. Hence $p_s$ is a **constant of
the motion inside the solenoid** — this is what makes the map exactly solvable
in closed form rather than only to some order.

Explicitly, from $H=\delta-p_s$:

$$
    x'=\frac{\partial H}{\partial p_x}=\frac{P_x}{p_s},\qquad
    y'=\frac{\partial H}{\partial p_y}=\frac{P_y}{p_s},
$$
$$
    p_x'=-\frac{\partial H}{\partial x}=\;\;\frac{k\,P_y}{p_s},\qquad
    p_y'=-\frac{\partial H}{\partial y}=-\frac{k\,P_x}{p_s} .
$$

Differentiating the kinetic momenta and substituting,

$$
    P_x'=p_x'+k\,y'=\frac{2k}{p_s}P_y,\qquad
    P_y'=p_y'-k\,x'=-\frac{2k}{p_s}P_x ,
$$

so $\left(P_x^2+P_y^2\right)'=0$ and therefore $p_s'=0$, as claimed. ✓

### 4.2 The rotation

With the constant

$$
    \boxed{\;\kappa \;=\; \frac{2k}{p_s} \;=\; \frac{k_s}{p_s}\;}
$$

and the complex combinations $w=x+iy$, $W=P_x+iP_y$, the equations become

$$
    W' = -i\kappa W ,\qquad w' = \frac{W}{p_s} ,
$$

whose exact solution over a length $L$ is

$$
    W(L)=W_0\,e^{-i\kappa L},\qquad
    w(L)=w_0+\frac{W_0}{p_s}\,\frac{1-e^{-i\kappa L}}{i\kappa} .
$$

### 4.3 The Larmor half-angle, and the factor-of-two check

Factor the displacement integral with $\theta=\kappa L$:

$$
    \frac{1-e^{-i\theta}}{i\kappa}
    =\frac{e^{-i\theta/2}\left(e^{i\theta/2}-e^{-i\theta/2}\right)}{i\kappa}
    =\frac{2\sin(\theta/2)}{\kappa}\;e^{-i\theta/2} ,
$$

so

$$
    \boxed{\;w(L)=w_0+\frac{W_0}{p_s}\;
    \frac{2\sin\!\left(\kappa L/2\right)}{\kappa}\;e^{-i\kappa L/2}\;}
$$

The displacement is along $W_0$ rotated by **half** the momentum rotation. That
is the Larmor half-angle, and it is the arithmetic check that the $k_s$ in the
potential and the $k_s$ in the momentum equation have not been confused: if the
half disappears, a factor of two is wrong somewhere in Section 2.

### 4.4 Longitudinal

$P_x,P_y$ do not depend on $\delta$, so

$$
    z'=\frac{\partial H}{\partial\delta}=1-\frac{1+\delta}{p_s} ,
$$

and since $p_s$ is constant,

$$
    z(L)=z_0+L\left(1-\frac{1+\delta}{p_s}\right),\qquad \delta(L)=\delta_0 .
$$

**Identical in form to the exact drift**, with $p_s$ built from the kinetic
rather than the canonical momenta. That is not a coincidence: the solenoid does
not change $|\mathbf P|$, so the path length per unit $s$ is the same function
of $p_s$ that it is in free space.

## 5. The hard edge is a coordinate change, not a kick model

Model the solenoid as $k_s$ constant on $[0,L]$ and zero outside, so
$\hat a_x=-ky\,\Theta(s)\Theta(L-s)$ is **discontinuous** at each face.

The canonical momenta are nevertheless **continuous** across a face: $p_x'$ and
$p_y'$ (Section 4.1) are bounded — a step function times a finite quantity —
and a bounded derivative cannot produce a jump. The **kinetic** momenta jump,
because $\hat a$ does:

$$
    \text{entrance }(s=0):\quad P_x=p_x+ky,\;\; P_y=p_y-kx ,
$$
$$
    \text{exit }(s=L):\quad p_x=P_x-ky,\;\; p_y=P_y+kx
    \quad\text{(evaluated at the \emph{exit} }x,y) .
$$

Physically this is the radial fringe field: $\nabla\cdot\mathbf B=0$ forces
$B_r=-\tfrac{r}{2}\,\mathrm dB_s/\mathrm ds$, and integrating that impulse
through an infinitely short edge gives exactly the transverse kick above. The
two descriptions are the same statement; the canonical one needs no separate
model and cannot get the sign inconsistent between the two faces.

**So the complete hard-edge solenoid map is three steps and no fringe element:**

1. **Entrance.** $P_x=p_x+ky$, $P_y=p_y-kx$; form $p_s$; form $\kappa=k_s/p_s$.
2. **Body.** Rotate $W$ by $-\kappa L$, advance $w$ by Section 4.3, advance $z$
   by Section 4.4.
3. **Exit.** $p_x=P_x-ky$, $p_y=P_y+kx$ at the new $x,y$.

Steps 1 and 3 are where "the fringe" lives. They are conversions, not physics
added on top.

## 6. Limits and checks

Each of these is cheap and each catches a distinct class of error.

**$k_s\to0$ reduces to the exact drift, not to a paraxial one.** As
$\kappa\to0$, $\frac{2\sin(\kappa L/2)}{\kappa}\to L$ and $e^{-i\kappa L/2}\to1$,
so $w=w_0+W_0L/p_s$ with $W_0=(p_x,p_y)$ and
$p_s=\sqrt{(1+\delta)^2-p_x^2-p_y^2}$ — term for term the $h=0$ branch of
`_lattice_drift`. This is the requirement that motivated deriving the exact map
in the first place: a solenoid at zero strength must not silently become a
different drift from the one the rest of the lattice uses.

**Symplecticity.** The map is the exact flow of a time-independent Hamiltonian,
so it is symplectic by construction, to roundoff and not to an order. It should
still be checked numerically by `SymplecticityContract`, because the *closed
form* can be implemented wrongly even when the derivation is right.

**Rotational invariance.** A solenoid is axisymmetric, so the map must commute
with a rotation about $s$. Any implementation error that treats $x$ and $y$
asymmetrically breaks this, and it is a one-line test.

**$\delta$ and amplitude dependence are present, not added.** $\kappa$ depends
on $p_s$, hence on $\delta$ and on $P_x,P_y$. The chromatic and amplitude
dependence of solenoid focusing therefore falls out of the exact map with no
extra terms.

### 6.1 The derivation was checked numerically before implementing

Every claim above was verified against a throwaway reference implementation of
Section 5, so the note is a checked result rather than an argument. Results, at
$k_s=1.7$, $L=1.3$, $\delta=4\times10^{-3}$ unless stated:

| check | result |
|---|---|
| closed form vs RK4 of Section 4.1's ODEs ($2\times10^5$ steps) | $6\times10^{-15}$ at $k_s=0.35$, $1.7\times10^{-14}$ at $k_s=1.7$ |
| $k_s=0$ vs `_lattice_drift(h=0)` | $8.7\times10^{-17}$ |
| $k_s=10^{-12}$ vs `_lattice_drift(h=0)` | $1.0\times10^{-15}$ |
| symplecticity, $\max\lvert M^{\mathsf T}JM-J\rvert$ | $1.3\times10^{-9}$ (finite-difference Jacobian at $h=10^{-7}$; this is the differencing noise, not the map) |
| rotational invariance about $s$ | $2.2\times10^{-19}$ |
| Larmor half-angle, displacement$/$(momentum rotation$/2$) | $1.000000000$ |

The last row is the factor-of-two check of Section 2 and it comes out exactly
unity, so the $k_s/2$ in the potential and the $k_s$ in the momentum equation
are consistent. The drift-limit rows are the requirement that motivated an exact
derivation at all: agreement is at roundoff, not at a tolerance.

## 7. What the paraxial matrix drops

The textbook solenoid matrix, with $K=k_s/2$, $C=\cos KL$, $S=\sin KL$:

$$
M=\begin{pmatrix}
C^2 & SC/K & SC & S^2/K\\
-KSC & C^2 & -KS^2 & SC\\
-SC & -S^2/K & C^2 & SC/K\\
KS^2 & -SC & -KSC & C^2
\end{pmatrix}
$$

is the $p_s\to1$ limit of Section 4. It sets $\kappa\to k_s$ and
$w'\to W$, i.e. it assumes $\delta=0$ **and** $P_x^2+P_y^2\ll1$. Dropping it
into Octopus would:

- lose the solenoid's natural chromaticity ($\kappa$ no longer depends on
  $\delta$);
- lose the amplitude dependence;
- and, worst, **fail to reduce to the exact drift at $k_s=0$**, so a lattice
  with a switched-off solenoid would disagree with the same lattice with the
  solenoid removed. That is the silent model-mixing the todo flagged, and it is
  why the matrix is recorded here only to be rejected.

Use it, if at all, only as an independent small-amplitude check of the exact
map.

## 8. Consequences for the rest of Octopus

**Splitting.** A split point inside a solenoid sits where $\hat a\neq0$, so the
two halves must exchange *kinetic* momenta, not canonical ones — equivalently,
splitting is only correct if each half applies its own entrance/exit conversion,
which then cancels at the interior face. The exact map needs no splitting for
accuracy, so the practical rule is: **do not split a solenoid**, and if an
aperture is wanted inside one, that is a modelling decision to be taken
deliberately rather than a free insertion.

**Diagnostics.** Any observer reading coordinates at a point inside a solenoid
reads canonical momenta. Emittance computed from them is not the physical
emittance. Because Octopus elements are entrance-to-exit maps and never expose
an interior state, this cannot happen today — but it becomes reachable the
moment a solenoid is split, which is a second reason for the rule above.

**Misalignment.** The existing `MisalignedElement` wrapper composes frame
changes outside the element map, and the solenoid map is a map like any other,
so misalignment should compose without special handling. This should be
*verified* rather than assumed, because a rotation about $s$ commutes with a
solenoid while a pitch does not, and a wrapper that silently assumed
commutation would be invisible on a roll test.

**Aperture.** Nothing special: the aperture element reads $x,y$, which are the
same in both momentum conventions.

## 9. Implementation notes

**Small $\kappa$.** $\frac{2\sin(\kappa L/2)}{\kappa}$ has a removable
singularity at $\kappa=0$ and loses digits to cancellation near it, exactly like
the $1/h$ forms in the lattice magnets. It is the *same function*:

$$
    \frac{2\sin(\kappa L/2)}{\kappa}=\frac{\sin\!\big((\kappa/2)L\big)}{\kappa/2}
    = \texttt{\_curv\_sin}(\kappa/2,\,L) ,
$$

so the existing small-argument-safe helper should be reused rather than a new
series written. That also means the solenoid inherits the tolerance already
chosen and tested there.

**Order of operations.** $p_s$ must be formed from the **kinetic** momenta after
the entrance conversion, never from the incoming canonical ones. Forming it
first is the single most likely implementation error, and it is invisible at
small amplitude because the two agree to first order in $k$.

**Suggested runtime.** A `Solenoid{M,T}` carrying `ks` and `L`, declaring
`Symplectic6DMap`, following `LatticeMagnet`'s pattern. No integrator steps and
no `nst`: the map is exact, so splitting it into steps would add error rather
than remove it.

### 9.1 Degenerate and boundary cases

Four cases the implementation meets and which the map above already answers, so
none of them needs a special branch.

**$L=0$ is the identity, for any $k_s$.** With $L=0$ the body does nothing
($W$ rotates by $-\kappa\cdot0$, $w$ is unchanged), so the exit conversion is
evaluated at the same $x,y$ as the entrance one and they cancel term by term:

$$
    p_x^{\text{out}} = P_x - ky = (p_x + ky) - ky = p_x .
$$

A zero-length solenoid is therefore a no-op rather than a fringe pair, which is
correct: two coincident faces with equal and opposite $\hat a$ jumps have no net
effect. **This is not the thin solenoid** of MAD-X, which holds
$k_s L=\texttt{KSI}$ fixed as $L\to0$ and is a genuinely different, non-identity
element. That is out of scope here; it needs its own limit taken with $\kappa L$
held constant, not $L\to0$ at fixed $k_s$.

**$k_s=0$ at finite $L$** is the exact drift, Section 6.

**Over-momentum particles throw, matching the drift.** If
$P_x^2+P_y^2>(1+\delta)^2$ the particle is moving transversely faster than its
total momentum allows and $p_s$ is imaginary. `_lattice_drift` raises a
`DomainError` in exactly this situation, so the solenoid does too and the
behaviour is uniform across the lattice. Worth recording rather than fixing
here: with the aperture work in place a particle that goes over-momentum through
a numerical blowup now *crashes the run* instead of being marked non-finite and
counted as a loss. That is a pre-existing property of every exact map in the
code, not something the solenoid introduces, and closing it would be a decision
about `sqrt` guards across all of `src/elements/`.

**Dead particles propagate.** A particle already carrying `NaN` produces `NaN`
throughout — every operation in the map is arithmetic on the incoming values,
with no comparison that could resurrect it — so a solenoid downstream of an
aperture leaves losses dead, as every other element does.

## 10. Validation plan

Following the bends, which reached $5\times10^{-13}$ against PTC:

1. **PTC/MAD-X reference.** Add cases to
   `validation/generate_ptc_reference.jl` with bodies `solenoid, l=..., ks=...`
   at several $k_s$ and at $\delta\neq0$, and extend
   `PTCConsistencyContract`. Pin the **sign** of $k_s$ there rather than by
   argument: the sign depends on charge convention and field direction, and
   agreement at one polarity proves nothing about the other, so scan both.
2. **Drift limit.** $k_s=0$ against `DriftSpec` of the same length, required to
   agree to roundoff, not to a tolerance.
3. **Symplecticity** and **rotational invariance** as in Section 6.
4. **Backend consistency** CPU vs CUDA, as for every other element.
5. **Paraxial cross-check.** At small amplitude and $\delta=0$, compare against
   the Section 7 matrix and confirm the difference scales as the amplitude and
   $\delta$ terms predict — a check that the exact map's extra content is the
   *expected* extra content.

## 11. Open questions

- **Soft fringe — one of four codes has anything, and it is a field map.** See
  Section 12: PTC, Bmad, MAD-X and Elegant's `SOLE` are all hard edge, and
  Bmad's source says the solenoid fringe *must always* be applied. Only
  Elegant's `MAPSOLENOID` is soft, and it gets there by numerically integrating
  a measured $(B_z,B_r)$ map rather than by an analytic soft-edge model. A soft
  model is physically meaningful — the radial field acts over a finite distance
  rather than as an impulse, and the difference grows with radius — but there is
  no closed form in these codes to port or check against. Scoped as its own todo
  item with the two possible shapes costed. The hard-edge map is written to be
  wrappable so a fringe model composes with it rather than interleaving.
- **Solenoid inside a bend.** The derivation above assumes $h=0$. A solenoid in
  a curved frame needs the $(1+hx)$ factor carried through, and the closed form
  above does not survive it unchanged. Out of scope; worth stating so nobody
  reads Section 4 as more general than it is.
- **Combined solenoid + multipole**, as in a detector-region final focus. The
  Hamiltonian is separable only if the multipole is treated as a kick, so this
  would be a Strang splitting of the exact solenoid with the existing multipole
  kick — feasible, but no longer an exact map, and the splitting error would
  need its own convergence study.

## 12. What the other codes do (read from source, 2026-08-01)

Checked against the trees in `Library/AcceleratorCodes/` rather than from
memory, because an earlier draft of Section 11 asserted that Bmad offered a soft
solenoid fringe and that is **wrong**.

**PTC** (`madx-5.03.06/libs/ptc/src/Sh_def_kind.f90`). The solenoid is `SOL5`
(`kind5`), tracked by `INTER_SOL5` as a Strang/Yoshida splitting of `KICK_SOL`
with `KICKMUL` at integrator methods 2, 4 and 6. `KICK_SOLR` opens with

```fortran
bsol = EL%B_SOL*EL%P%CHARGE
xp   = x(2) + bsol*x(3)/2.0_dp
yp   = x(4) - bsol*x(1)/2.0_dp
```

which is `_solenoid_edge` **including the signs** — PTC forms the kinetic
momentum exactly as Section 5 derives it. With `EL%p%exact` it then builds
`h = sqrt((1+x(5))^2 - xp^2 - yp^2)`, our $p_s$; without it, `h = 1 + x(5)`, the
paraxial form Section 7 rejects. The body is a Larmor rotation by
`ANG = yh*bsol/2` — the **half** angle — composed with a focusing advance, which
is the rotating-frame decomposition rather than our direct closed form. The two
are algebraically equivalent and agree to $4.9\times10^{-13}$, so each
cross-checks the other.

**PTC has no solenoid fringe routine.** Its entire fringe inventory is
`FRINGE_CAV_TRAV` (travelling-wave cavity), `FRINGE__MULTI` (the
Forest–Milutinović multipole fringe) and `fringe_helr` (helical dipole, whose
body is wrapped in `if(.false.)` and is dead code). The solenoid's fringe is the
hard-edge conversion inside `KICK_SOL` and nothing else.

**Bmad** (`bmad/low_level/apply_element_edge_kick.f90`). `apply_this_sol_fringe`
applies

```fortran
ks4 = at_sign * charge * bs_field * c_light / (4*p0c)
orb%vec(2) = orb%vec(2) + ks4 * xy_orb(2)
orb%vec(4) = orb%vec(4) - ks4 * xy_orb(1)
```

i.e. $k_s/4$ applied symmetrically about the spin kick, $k_s/2$ in total — our
$k$, with our signs. It is **hard edge and mandatory**: the source comment reads
*"With a solenoid must always apply the fringe kick due to the longitudinal
field."* Bmad's `soft_edge_only` / `full` / `sad_full` `fringe_type` values exist
for the multipole and SAD fringes; `apply_this_sol_fringe` has no `fringe_type`
branch at all.

**Three consequences worth carrying.**

1. **Three independent codes agree on the sign and magnitude** of the edge
   conversion, which is the strongest available check on Section 5 short of the
   PTC benchmark itself.
2. **The fringe being mandatory is not an Octopus opinion.** Bmad says it in a
   comment, PTC enforces it structurally by burying the conversion inside the
   body integrator. `SolenoidSpec` having no switch to disable it matches both.
3. **PTC already does combined solenoid + multipole**, through the
   `KICK_SOL`/`KICKMUL` splitting, at Yoshida orders 2/4/6. Section 11 lists that
   as out of scope for Octopus; it is worth recording that a validated precedent
   exists and what shape it takes, so the work is a port rather than a design if
   it is ever wanted.

**Elegant** (`elegant/src/track_data.c`). Two solenoid elements, and this is the
one code of the four that has something soft — though not in the form the
question implies.

`SOLE` is the plain one, and its own description is *"A solenoid implemented as
a **matrix, up to 2nd order**"* — the paraxial form Section 7 rejects, carried to
second order. Its parameter list is `L, KS, B, DX, DY, DZ, ORDER` with **no
fringe parameter at all**, which is conspicuous next to Elegant's own `HCOR`,
which does carry an `EDGE_EFFECTS` switch. So Elegant's ordinary solenoid has no
fringe control and a less accurate body than ours.

> **Trap — Elegant's `KS` has the opposite sign.** Its parameter table defines
> `KS` as *"geometric strength, $-B_s/(B\rho)$"*, against MAD-X's
> $+B_s/(B\rho)$. Octopus follows MAD-X, which is what the PTC benchmark pins.
> Anyone cross-checking a lattice against Elegant must flip the sign, and the
> error is invisible in every quantity even in $k_s$.

`MAPSOLENOID` is the soft one: *"A numerically-integrated solenoid specified as
a map of $(B_z, B_r)$ vs $(z, r)$."* It reads an SDDS field map and integrates
it with Runge–Kutta, Bulirsch–Stoer, non-adaptive Runge–Kutta or modified
midpoint, under an `ACCURACY` tolerance, with misalignments and an optional
superimposed uniform field.

**So a real fringe exists in exactly one of the four codes, and it is a field-map
integrator rather than an analytic soft-edge map.** That distinction decides what
"add a soft fringe" would mean for Octopus, and it is why the todo entry lists
two different pieces of work rather than one.

## 13. The curved frame: a solenoid with $h\neq0$ is not what it sounds like

Every other Octopus lattice element takes a frame curvature $h$, and the
conventions note is emphatic that **$h$ is a property of the frame, not of the
magnet**. So the natural next step is a solenoid with $h\neq0$. It does not work,
and the reason is physics rather than algebra.

### 13.1 Constant $B_s$ in a curved frame is not a vacuum field

Take the field to be longitudinal in the curved frame, $\mathbf B=B_s\hat e_s$,
with $B_s$ constant — the obvious reading of "a solenoid in a curved frame".
Work in cylindrical coordinates about the bend centre, where $\hat e_s=\hat
e_\varphi$ and $R=\rho+x=(1+hx)/h$:

$$
    (\nabla\times\mathbf B)_Y=\frac{1}{R}\frac{\partial\left(R\,B_\varphi\right)}{\partial R} .
$$

For constant $B_s$ this is $B_s/R\neq0$. **The field requires a current density
throughout the beam pipe, so it is not a vacuum field and no magnet produces
it.** Verified numerically at $\rho=2$, $x=0.3$: $|\nabla\times\mathbf B|=0.4348$
against the predicted $B_s/R=1/2.3=0.4348$, while $\nabla\cdot\mathbf B=0$
exactly — so it is the curl, not the divergence, that fails.

### 13.2 What *is* consistent is a toroidal field, which is a different magnet

$(\nabla\times\mathbf B)_Y=0$ forces $R\,B_\varphi=\text{const}$, i.e.

$$
    B_s=\frac{B_0}{1+hx} .
$$

Numerically curl-free to $2.5\times10^{-11}$, and divergence-free for the same
reason as before. But this is the field of a **current filament along the bend
axis** — a toroidal field, the thing that fills a tokamak, not a solenoid. Its
magnitude falls across the aperture as $1/R$ and it has no straight-solenoid
limit at fixed $B_0$ other than $h\to0$.

So "add $h$ to the solenoid" does not generalize the solenoid. It builds a
toroidal magnet, and calling it a solenoid would be exactly the silent
model-mixing that Section 7 rejects the paraxial matrix for.

### 13.3 A real solenoid traversed by a curved orbit is a different problem again

The physically common case — a detector solenoid with a crossing angle, the one
that motivates asking — is a **straight** solenoid whose axis does not coincide
with a curved reference orbit. Its field is still $B_s\hat e_z$ about *its own*
straight axis; it is the *frame* that curves relative to it. Expanded in the
curved frame that field is not longitudinal at all: it acquires $x$ and $s$
components that vary along the element.

That is a frame problem, not a curvature problem: a straight solenoid entered at
an angle is a **patch, a straight-frame solenoid, and a patch back**. Adding $h$
to `Solenoid` would not describe this case and would not help it.

> **A patch element does not exist yet.** `MisalignedElement` is not a
> substitute: a misalignment is an *error* in where one magnet sits, restoring
> the frame afterwards, while a patch is a *deliberate* transition to a new
> reference frame that persists. Section 7.5 of
> [`misalignment_and_patch_maps.md`](misalignment_and_patch_maps.md) already
> recommends building one; see the `patch` item in `docs/todo.md`. Until then
> the crossing-angle solenoid has no clean expression — which is a reason to
> build the patch, not a reason to add $h$ to the solenoid.

### 13.4 If the toroidal element is wanted anyway

It is a legitimate magnet, just not a solenoid, and it would need its own
element. Two things make it much harder than the straight case, and both should
be priced before starting:

**No closed form.** The vector potential of $B_s=B_0/(1+hx)$ satisfies
$\partial_x\hat a_y-\partial_y\hat a_x=k_s/(1+hx)$, giving for instance
$\hat a_y=(k_s/h)\ln(1+hx)$. That logarithm enters the Hamiltonian's square root,
so the kinetic momentum no longer rotates rigidly and $p_s$ no longer closes the
system in the way Section 4 relies on. The map would need an integrator with
`nst` and an integrator order, like the bends, rather than being exact like the
straight solenoid.

**Nothing validates it.** PTC's `SOL5` carries no curvature — its type holds
`L`, `B_SOL`, `AN`/`BN`, fringe fudges and offsets, and `GETMULB_SOL` evaluates a
straight multipole field with no $(1+hx)$ anywhere. Bmad, MAD-X and Elegant are
likewise straight-frame only. The only available check is the one this project
already uses for unvalidatable cases: **agreement with the $h=0$ map as
$h\to0$**, which tests the limit and the implementation but not the curved
physics itself.

> **Correction (2026-08-02): the recommendation below was wrong and is
> withdrawn.** Calling the curved field "a toroidal magnet, not a solenoid" was
> a false distinction -- **a solenoid bent around an arc *is* a toroidal
> field**, and the `1/R` falloff is what bending one physically does. The
> Maxwell analysis above stands; the conclusion drawn from it did not.
> `B_s = B_0/(1+hx)` satisfies Maxwell in the curved frame and reduces to `B_0`
> on the reference orbit and as `h -> 0`, which is exactly the construction the
> `psi` table already uses for curved multipoles. A curved solenoid is
> therefore well posed; it is simply not closed-form, and needs an integrator as
> the curved multipoles do. See `docs/todo.md`.

**Superseded recommendation: do not add `h` to `Solenoid`.** It would name a toroidal magnet
after a solenoid. If a curved-orbit solenoid study appears, reach for the patch
maps first, which describe the real geometry; and if a genuine toroidal element
is ever needed, give it its own name, its own integrator, and this section as the
statement of what it is.

## 14. Superimposed multipoles

A detector-region final focus superimposes quadrupole (and higher) fields on the
solenoid, and PTC's `SOL5` carries `AN`/`BN` for exactly that. Implemented as
`SolenoidSpec(; kn, kskew, nst)` plus the named `k0/k1/k2…` and `k0s/k1s/k2s…`
the thick magnets already take.

**This is the one place the solenoid stops being exact.** The solenoid rotates
the frame the multipole kicks in, so the two pieces do not commute and no closed
form exists. Second-order Strang over `nst` steps:

$$
    \left[\;S(d/2)\;K(d)\;S(d/2)\;\right]^{n_{\rm st}},\qquad d=L/n_{\rm st},
$$

with $S$ the exact map of Section 4 and $K$ the same `_lattice_kick` every thick
magnet uses. Structurally this is what PTC's `INTER_SOL5` does, interleaving
`KICK_SOL` with `KICKMUL` at Yoshida orders 2, 4 and 6; ours is order 2 only.

**The interior fringes cancel, and they must.** Each $S$ applies an entrance and
an exit conversion, so a naive reading would have $2n_{\rm st}$ fringes. They
cancel in pairs because $K$ changes momenta but **not** positions, so the exit
conversion of one step and the entrance conversion of the next are evaluated at
the same $x,y$ and undo each other exactly. What survives is one entrance
conversion and one exit conversion, which is the physical content. The same
argument shows the kick may be applied to canonical or kinetic momenta
indifferently: a multipole's own potential is longitudinal, so it shifts both by
the same amount.

### 14.1 Strengths are thick, and `ks` had to move

Multipole strengths follow `QuadrupoleSpec`: **thick** $K_n$, not the thin
family's integrated $K_nL$. A solenoid has a length, so this is the consistent
choice, and confusing the two is a factor of $L$.

That forced a naming decision, and **MAD-X made the same one**. Its solenoid
dictionary reads

```c
"ksi = [r, 0],  " /* was: ksl, but that clashes with naming conventions of multipoles */
```

so MAD-X renamed the solenoid's *integrated* strength away from `ksl` for
precisely the clash we hit: `ks` cannot simultaneously mean the solenoid
strength and the skew multipole tuple. Octopus keeps `ks` for the solenoid — the
name the rest of the world uses for it, and what the PTC benchmark pins — and
spells the skew tuple `kskew`. Users normally reach it through `k1s`/`k2s` and
never see the difference.

One asymmetry worth knowing when writing MAD-X input: **MAD-X's solenoid takes
the integrated `knl`/`ksl`, not the thick `k1` its quadrupole takes.**
`solenoid, k1=0.6` is rejected as an illegal keyword. The benchmark cases
therefore carry `knl = k1*L` in the MAD-X body against `k1` in the Octopus spec.

### 14.2 Verification

- **PTC**: $4.7\times10^{-13}$ at `nst=8` and $3.6\times10^{-13}$ at `nst=32`,
  against `solenoid, l=1.3, ks=0.35, knl={0.0, 0.78}`. Two step counts, so the
  comparison tests convergence and not one working point. Contract now 41 cases.
- **Reduces to a quadrupole**: `ks=0` with `k1` reproduces `QuadrupoleSpec` to
  $7\times10^{-18}$ — the splitting collapses to the thing it splits.
- **Reduces to the exact solenoid**: any all-zero multipole set returns the
  `N = 0` runtime and is bit-identical to the pure element.
- **Order two**: quadrupling `nst` cuts the error by $16.0$–$16.5$, measured
  across three decades.
- **Symplectic** at every step count, as a Strang product of symplectic maps
  must be.

## 15. The curved frame, done properly (2026-08-02)

Section 13's *analysis* was right and its *conclusion* was wrong (see the
correction box there). This section supplies what a curved solenoid actually
needs.

### 15.1 Potential, chosen to reduce to the symmetric gauge

The Maxwell-consistent field is $B_s=B_0/(1+hx)$ (Section 13.2). Its potential is
fixed only up to a gauge, and the gauge is not free to choose casually: it sets
what the canonical momenta *mean*, so it must reduce to Section 2's symmetric
gauge as $h\to0$ or the flat limit will not match the existing implementation.
Take

$$
    \hat a_x=-k\,y ,\qquad
    \hat a_y=k\,g(x) ,\qquad
    g(x)=\frac{2}{h}\ln(1+hx)-x ,\qquad k=\tfrac{k_s}{2} .
$$

Check the field: $\partial_x\hat a_y-\partial_y\hat a_x = k\,g'(x)+k$ with
$g'(x)=\frac{2}{1+hx}-1$, giving $k\cdot\frac{2}{1+hx}=\frac{k_s}{1+hx}$. ✓
And $g(x)\to x$ as $h\to0$, so $\hat a\to(-ky,\,kx)$, the symmetric gauge. ✓

### 15.2 Equations of motion

With $P_x=p_x-\hat a_x=p_x+ky$, $P_y=p_y-\hat a_y=p_y-k\,g(x)$ and
$p_s=\sqrt{(1+\delta)^2-P_x^2-P_y^2}$, the curved-frame Hamiltonian
$H=\delta-(1+hx)\,p_s$ gives

$$
\begin{aligned}
    x' &= (1+hx)\,\frac{P_x}{p_s}, &\qquad
    y' &= (1+hx)\,\frac{P_y}{p_s},\\
    p_x' &= h\,p_s+(1+hx)\,k\,g'(x)\,\frac{P_y}{p_s}, &\qquad
    p_y' &= -(1+hx)\,k\,\frac{P_x}{p_s},\\
    z' &= 1-(1+hx)\,\frac{1+\delta}{p_s}, &\qquad
    \delta' &= 0 .
\end{aligned}
$$

Written in the kinetic momenta these collapse, using $k(g'+1)=k_s/(1+hx)$:

$$
    P_x'=h\,p_s+\frac{k_s}{p_s}P_y,\qquad
    P_y'=-\frac{k_s}{p_s}P_x,\qquad
    p_s'=-h\,P_x .
$$

**Two rotations at once**: the solenoid mixes $P_x$ with $P_y$ at rate
$\kappa=k_s/p_s$, while the frame curvature mixes $P_x$ with $p_s$ at rate $h$.
Setting $h=0$ recovers Section 4 exactly (and $p_s$ becomes conserved again);
setting $k_s=0$ recovers the curved drift.

### 15.3 Why there is no closed form, and no exact splitting either

$p_s$ is **not** conserved when $h\neq0$ — the frame rotation feeds $P_x$ into
$p_s$ — so the mechanism that made Section 4 solvable is gone. That alone would
be survivable; what rules out the usual accelerator remedy is that
**$H$ does not split into two exactly-solvable pieces.**

Every other curved element in Octopus splits as
*(exact curved drift)* $+$ *(kick from $\hat a_s$)*, which works because a
multipole's potential is purely longitudinal and therefore position-only. A
solenoid's potential is **transverse**, so it sits inside the square root and no
gauge transformation can move it out: $\hat a_x=\hat a_y=0$ would give
$B_s=0$. Writing $H_A$ for the curved drift and $H_B$ for the straight solenoid,
$H_A+H_B$ carries two square roots where $H$ has one, so composing those two
exact maps converges to the wrong Hamiltonian rather than merely slowly.

That is the real reason no code implements this, and it is worth stating so the
obvious "just Strang-split the two maps we already have" is not attempted.

### 15.4 What is implemented: implicit midpoint

A **general** symplectic integrator is therefore required rather than a splitting
one. `Solenoid` with $h\neq0$ uses the **implicit midpoint rule**,

$$
    u_{n+1}=u_n+\Delta\,f\!\left(\tfrac{u_n+u_{n+1}}{2}\right),
$$

over `nst` steps, with the implicit stage solved by a fixed number of fixed-point
iterations. Implicit midpoint is symplectic for *any* Hamiltonian, second-order
accurate, and time-reversible, which is what makes it the right tool once
splitting is unavailable. The cost is the iteration — several evaluations of $f$
per step where a split integrator needs one — and that cost is the price of
curvature, accepted deliberately for consistency with the rest of the lattice.

$g(x)=\frac{2}{h}\ln(1+hx)-x$ carries a removable $1/h$, handled by the same
small-argument branching the curvature helpers already use.

### 15.5 Validation

Nothing external implements a curved solenoid — PTC's `SOL5` carries no
curvature and neither do Bmad, MAD-X or Elegant — so the checks are internal and
were chosen to pin different failure modes:

- **$h\to0$ against the exact straight map.** The integrator must converge to
  Section 4's closed form, which is the check the whole request was premised on.
- **$k_s\to0$ against the exact curved drift** `_lattice_drift(h, L, …)`.
- **Second-order convergence** in `nst`, against a finely-integrated reference.
- **Symplecticity** at coarse `nst`, which a non-symplectic integrator such as
  RK4 would fail while still converging — this is the check that says the
  integrator is the one claimed.
