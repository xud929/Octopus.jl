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

- **Soft fringe.** The hard edge is a model. A real solenoid has a finite
  transition over which $B_s$ rises, and there the radial field does work in a
  way the impulsive conversion does not capture at large radius. MAD-X and PTC
  both offer hard-edge solenoids only; Bmad has a soft option. Deferred, but the
  hard-edge map should be written so a fringe model can wrap it rather than be
  interleaved.
- **Solenoid inside a bend.** The derivation above assumes $h=0$. A solenoid in
  a curved frame needs the $(1+hx)$ factor carried through, and the closed form
  above does not survive it unchanged. Out of scope; worth stating so nobody
  reads Section 4 as more general than it is.
- **Combined solenoid + multipole**, as in a detector-region final focus. The
  Hamiltonian is separable only if the multipole is treated as a kick, so this
  would be a Strang splitting of the exact solenoid with the existing multipole
  kick — feasible, but no longer an exact map, and the splitting error would
  need its own convergence study.
