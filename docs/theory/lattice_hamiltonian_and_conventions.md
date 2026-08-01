# Lattice Hamiltonian, Multipole Strengths, and Longitudinal Conventions

Reference note for lattice-magnet tracking: the curvilinear Hamiltonian, the
four longitudinal coordinate conventions used by the codes we benchmark
against, the exact conversions between them, and the multipole strength
definitions that must be pinned before any of it is implemented.

This note exists because three independent factor-of-$n$ traps live in this
territory — the $n!$ in the field expansion, the index offset between
$K_n$ and $b_n$, and the $\beta_0$ scalings between longitudinal pairs — and
each of them produces a result that looks plausible and is wrong.

Scope: single-particle magnet optics. The beam-beam element has its own
conventions, derived in [Synchro-Beam Longitudinal Kick](beam_beam_longitudinal_kick.md)
and [Weak–Strong Six-Dimensional Source Model](weak_strong_6d_model.md).

## 1. The curvilinear Hamiltonian

With $s$ as independent variable, potentials normalized by the reference
momentum $P_0$,

$$
    \hat\phi=\frac{q\phi}{P_0},\qquad
    \hat a_i=\frac{q}{P_0}\,\mathbf A\cdot\mathbf e_i,\quad i\in\{x,y,s\},
$$

the Hamiltonian in a frame of horizontal curvature $h=1/\rho_{\rm ref}$ is

$$
    H=-\left(1+hx\right)\left[\hat a_s+
      \sqrt{\left(p_t+\tfrac{1}{\beta_0}-\hat\phi\right)^2
            -\tfrac{1}{\beta_0^2\gamma_0^2}
            -\left(p_x-\hat a_x\right)^2-\left(p_y-\hat a_y\right)^2}\right],
$$

with the longitudinal pair $\left(q_t=-ct,\ p_t=\Delta E/(P_0c)\right)$. The
factor $(1+hx)$ multiplies $\hat a_s$ as well as the square root, because the
canonical momentum conjugate to $s$ carries the metric factor of the curvilinear
frame.

**$h$ is a property of the frame, not of the magnet.** It says where the
reference trajectory curves. The field strength is separate — see Section 4 —
and the two need not agree.

## 2. Longitudinal conventions

Four canonical pairs are in use. All four are related to $(q_t,p_t)$ by
generating functions, so all four are exactly symplectic; they differ in what
is convenient, not in what is correct.

| # | coordinate | momentum | new Hamiltonian |
|---|---|---|---|
| 1 | $z_1=\dfrac{s}{\beta_0}+q_t=-c\,\Delta t$ | $p_{z,1}=p_t=\dfrac{\Delta E}{P_0c}$ | $H+\dfrac{p_{z,1}}{\beta_0}$ |
| 2 | $z_2=s+\beta_0 q_t=-\beta_0c\,\Delta t$ | $p_{z,2}=\dfrac{p_t}{\beta_0}=\dfrac{\Delta E}{\beta_0P_0c}$ | $H+p_{z,2}$ |
| 3 | $z_3=s+\beta q_t=s-\ell$ | $p_{z,3}=\delta=\dfrac{\Delta P}{P_0}$ | $H+p_{z,3}$ |
| 4 | $z_4=\dfrac{s\beta}{\beta_0}+\beta q_t=-\beta c\,\Delta t$ | $p_{z,4}=\delta$ | $H+\dfrac{p_t}{\beta_0}$ |

with $\ell=\beta ct$ the path length actually travelled and
$\Delta t=t-s/(\beta_0c)$ the arrival-time offset from the reference particle.

The generating functions are $F_1=-(z-s/\beta_0)p_t$, $F_2=-(z-s)p_t/\beta_0$,
$F_3=-(z-s)\delta$, and $F_4=-z\delta+sp_t/\beta_0$. Symplecticity of #3 and #4
rests on

$$
    \delta=-1+\sqrt{\left(\tfrac{1}{\beta_0}+p_t\right)^2-\tfrac{1}{\beta_0^2\gamma_0^2}},
    \qquad
    \frac{\mathrm d\delta}{\mathrm dp_t}=\frac{1}{\beta},
$$

which makes each longitudinal Jacobian $\beta\cdot\beta^{-1}=1$.

### 2.1 Which code uses which

| convention | code | names |
|---|---|---|
| **#1** | MAD-X, PTC `TIME=TRUE` | `T`, `PT` |
| **#1** | Xsuite | $\tau$, $p_\tau$ |
| **#2** | SixTrack | $\sigma$, $p_\sigma$ |
| **#2** | Xsuite (default state) | `zeta`, $p_\zeta$ |
| **#3** | PTC `TIME=FALSE` | $-$pathlength, $\delta_p$ |
| **#4** | Bmad | $z$, $p_z$ |
| **#4** | Xsuite | $\xi$, `delta` |

Two traps follow directly.

> **Xsuite's `zeta` and `delta` are not a canonical pair.** `zeta` is convention
> #2, whose conjugate is $p_\zeta$; `delta` is the conjugate of $\xi$
> (convention #4). The Xsuite physics manual is explicit that treating
> $(\zeta,\delta)$ as conjugate is the small-$\delta$ approximation
> $\delta\simeq p_\zeta$. Any benchmark that reads `zeta` and `delta` out of
> Xsuite and feeds them to a canonical map is mixing two conventions.

> **PTC's `TIME=FALSE` variable is $-\ell$, not $s-\ell$.** Same dynamics —
> they differ by the parameter $s$ — but different printed numbers. The offset
> has to be pinned when comparing element-by-element output. It also carries an
> **orientation**: PTC's maps are symplectic with respect to $S_{56}=-1$, so a
> port to $z=s-\ell$ with the usual $S_{56}=+1$ must flip the sign of every
> longitudinal update. Measured in Section 6.4.

### 2.2 Conversions

Everything routes through $p_t$:

$$
    p_t=\frac{\Delta E}{P_0c},\qquad
    \frac{E}{P_0c}=\frac{1}{\beta_0}+p_t,\qquad
    1+\delta=\sqrt{\left(\tfrac{1}{\beta_0}+p_t\right)^2-\tfrac{1}{\beta_0^2\gamma_0^2}},
$$

$$
    \beta=\frac{Pc}{E}=\frac{1+\delta}{\tfrac{1}{\beta_0}+p_t},
    \qquad
    p_t=-\frac{1}{\beta_0}+\sqrt{(1+\delta)^2+\frac{1}{\beta_0^2\gamma_0^2}} .
$$

Coordinates then follow from the table: $z_2=\beta_0z_1$,
$z_3=z_1\beta - s(\beta/\beta_0-1)$, $z_4=\beta z_1$, and momenta from
$p_{z,2}=p_{z,1}/\beta_0$, $p_{z,3}=p_{z,4}=\delta(p_t)$.

Each conversion costs one square root. Applied once per cavity rather than once
per magnet, that is free.

## 3. Which convention to track in

**Magnets in #3, cavities in #1.** The reasoning is worth writing down because
it is not a matter of taste:

- In a magnet nothing accelerates, so $\delta$ is a **constant of motion**. The
  exact drift and bend integrals close in elementary functions precisely
  because $p_z$ and $p_y$ drop out as constants (Section 5). Rigidity enters as
  $B\rho\propto P$, so multipole kicks scale by $1/(1+\delta)$ directly — no
  conversion inside the kernel.
- In a cavity the energy changes, and the natural pair is
  (arrival time, energy). In convention #1 the cavity map is a one-line update
  of $p_t$ at fixed $z_1$. Expressed in $\delta$ it acquires the square root at
  every kick.

This is exactly PTC's `TIME` switch, and the conversion between them is an
exact canonical transformation — nothing is lost at the boundary. **Convert at
the cavity, not per element.**

## 4. Multipole strength definitions

### 4.1 The MAD-X / PTC / Xsuite convention (with $n!$)

$$
    B_y+iB_x=\sum_{n\ge0}\frac{B_n+iA_n}{n!}(x+iy)^n,
    \qquad
    B_n=\left.\frac{\partial^nB_y}{\partial x^n}\right|_0,\quad
    A_n=\left.\frac{\partial^nB_x}{\partial x^n}\right|_0 ,
$$

normalized by the reference rigidity $(B\rho)_0=P_0/q$:

$$
    K_n=\frac{B_n}{(B\rho)_0},\qquad \hat K_n=\frac{A_n}{(B\rho)_0},
$$

giving the normalized longitudinal potential

$$
    \boxed{\;\hat a_s(x,y)=-\,\Re\sum_{n\ge0}\frac{K_n+i\hat K_n}{(n+1)!}(x+iy)^{n+1}\;}
$$

**Index: $n=0$ dipole, $n=1$ quadrupole, $n=2$ sextupole, $n=3$ octupole.**
MAD-X exposes `K0,K1,K2,K3` (normal) and `K0S,K1S,…` (skew); `KNL`/`KSL` are
the same quantities integrated over the length.

### 4.2 The magnet-measurement convention (relative $b_n$, $a_n$)

$$
    B_y+iB_x=B_{\rm main}\sum_{m\ge1}(b_m+ia_m)\left(\frac{x+iy}{R_{\rm ref}}\right)^{m-1},
$$

dimensionless, quoted at a reference radius $R_{\rm ref}$, usually in units of
$10^{-4}$. **Index: $m=1$ dipole, $m=2$ quadrupole** — offset by one from
$K_n$, and with no factorial.

Matching term by term at $n=m-1$:

$$
    \boxed{\;K_n=\frac{n!\;B_{\rm main}}{(B\rho)_0}\cdot\frac{b_{n+1}}{R_{\rm ref}^{\,n}}\;}
$$

Both the $n!$ and the index shift are in that one line. It is the single most
error-prone conversion in the note; it belongs in code with a test, not in a
comment.

### 4.3 Two checks against the source derivation

**The sextupole $\lambda$.** Writing the sextupole potential as
$\hat a_s=-\frac{\lambda}{3}\left(x^3-3xy^2\right)$ and comparing with the boxed
expression at $n=2$, $-\Re\frac{K_2}{3!}(x+iy)^3=-\frac{K_2}{6}(x^3-3xy^2)$:

$$
    \lambda=\frac{K_2}{2}.
$$

The $\lambda$ parameterization is **half** the MAD-X $K_2$. Fix one convention
in the element spec and convert at the boundary.

**A sign correction.** From $H=1+p_z-\hat a_s-\sqrt{\cdots}$ we have
$\partial H/\partial x=-\partial\hat a_s/\partial x$, hence

$$
    \frac{\mathrm dp_x}{\mathrm ds}=-\frac{\partial H}{\partial x}
    =+\frac{\partial\hat a_s}{\partial x}=-\lambda\left(x^2-y^2\right),
    \qquad
    \frac{\mathrm dp_y}{\mathrm ds}=+2\lambda xy .
$$

The source derivation carries these with the opposite sign. The signs above are
the ones consistent with the Lorentz force — a particle moving along $+\mathbf
e_s$ through $B_y>0$ feels $\mathbf F\propto\mathbf e_s\times\mathbf
e_y=-\mathbf e_x$ — and with the standard MAD-X thin-sextupole kick
$\Delta p_x=-\frac{K_2L}{2}(x^2-y^2)$, $\Delta p_y=K_2Lxy$.

### 4.4 Multipoles in a curved frame

The expansion of Section 4.1 solves Laplace's equation in a *straight* frame.
It is not a solution when $h\neq0$, so it cannot be used for a combined-function
bend — or for any element that carries curvature, which in this design includes
drifts and quadrupoles.

**The governing equation.** With scale factors $(1,1,1+hx)$, $\mathbf A=A_s\mathbf
e_s$ and $\partial_s=0$, the curl in curvilinear coordinates gives

$$
    \hat B_x=\frac{\partial_y\Psi}{1+hx},\qquad
    \hat B_y=-\frac{\partial_x\Psi}{1+hx},\qquad
    \hat B_s=0,
    \qquad\text{where}\quad \Psi\equiv(1+hx)\,\hat a_s .
$$

$\Psi$ is exactly the combination the Hamiltonian carries — the potential term
in Section 1 is $-(1+hx)\hat a_s=-\Psi$ — so it is the natural unknown.
Imposing $\nabla\times\mathbf B=0$ yields

$$
    \boxed{\;\partial_x^2\Psi+\partial_y^2\Psi-\frac{h}{1+hx}\,\partial_x\Psi=0\;}
$$

which reduces to Laplace's equation at $h=0$.

**Fixing what $K_n$ means.** The decomposition into multipole orders is not
unique once $h\neq0$; solutions differing by a harmonic function are equally
valid and codes disagree here. Pin it by the **midplane field**, the direct
generalization of Section 4.1:

$$
    \hat B_y(x,0)=\sum_{n\ge0}\frac{K_n}{n!}x^n .
$$

Since $\partial_x\Psi(x,0)=-(1+hx)\hat B_y(x,0)$, this integrates in closed form:

$$
    \boxed{\;\Psi(x,0)=-\sum_{n\ge0}\frac{K_n}{n!}
      \left[\frac{x^{n+1}}{n+1}+\frac{h\,x^{n+2}}{n+2}\right]\;}
$$

**Extending off the midplane.** Writing $\Psi=\sum_k\frac{y^k}{k!}\Psi_k(x)$ and
substituting into the PDE gives an **exact recursion — no expansion in $h$**:

$$
    \boxed{\;\Psi_{k+2}(x)=-\Psi_k''(x)+\frac{h}{1+hx}\,\Psi_k'(x)\;}
$$

seeded by $\Psi_0(x)=\Psi(x,0)$ above (even $k$: normal multipoles; odd $k$ is
the same recursion seeded from $\hat B_x(x,0)$ for skew).

The first correction has a compact closed form,

$$
    \Psi_2=(1+hx)\sum_{n\ge1}\frac{K_n}{(n-1)!}x^{n-1}=(1+hx)\,\hat B_y'(x,0),
$$

which shows immediately why the **dipole terminates**: that sum starts at
$n\ge1$ and is empty for pure $K_0$, so every $\Psi_k$ with $k\ge2$ vanishes and

$$
    \Psi=-K_0\left(x+\frac{hx^2}{2}\right)
$$

*exactly* — reproducing the bend potential of Section 5 with no truncation. For
$n\ge1$ the series does not terminate. The curved quadrupole, for example:

$$
    \Psi_0=-K_1\!\left(\frac{x^2}{2}+\frac{hx^3}{3}\right),\quad
    \Psi_2=K_1(1+hx),\quad
    \Psi_4=\frac{K_1h^2}{1+hx},
$$
$$
    \Psi_6=\frac{-3K_1h^4}{(1+hx)^3},\qquad
    \Psi_8=\frac{45K_1h^6}{(1+hx)^5}.
$$

**Three consequences for the implementation.**

1. **$\Psi$ is polynomial only for the dipole.** From $\Psi_4$ onward the terms
   carry $(1+hx)^{-m}$, inherited from the recursion's $h/(1+hx)$. Any
   implementation that assumes a polynomial potential is a straight-frame
   implementation.
2. **The $y$-truncation order is a convergence parameter**, like the step count
   `ns` — not a fixed choice. It should be exposed, defaulted from a measured
   error at the working aperture, and swept in the same convergence study.
3. **Curvature is free when there is no field.** All $K_n=0$ gives $\Psi\equiv0$,
   so a curved drift costs nothing beyond the exact drift map of Section 5. This
   is what makes $h$ safe to carry on every element rather than only on bends.

**Verification.** The dipole solution reproduces Section 5's $\hat a_s$ to
$0$ ulp; the quadrupole PDE residual falls as $y^{k_{\max}}$ with truncation
order ($y^2$ and $y^4$ scaling confirmed, higher orders reaching the
finite-difference floor); the midplane field matches its definition to
$4\times10^{-13}$ for $h$ up to $0.9$; and $h\to0$ recovers
$-\Re\!\left[K_1w^2/2\right]$ to $5\times10^{-14}$.

### 4.5 The thin multipole kick

Splitting $H=H_{\rm drift}+H_{\rm kick}$ with $H_{\rm kick}=-\Psi$, a kick of
length $L$ is

$$
    \Delta p_x=L\,\partial_x\Psi=-L\,(1+hx)\,\hat B_y,
    \qquad
    \Delta p_y=L\,\partial_y\Psi=+L\,(1+hx)\,\hat B_x ,
$$

which for $h=0$ collapses to the complex form

$$
    \boxed{\;\Delta p_x-i\,\Delta p_y=-L\sum_{n\ge0}\frac{K_n+i\hat K_n}{n!}(x+iy)^n\;}
$$

The $hp_s$ term of Section 5 belongs to the **drift**, not the kick — it is the
frame rotation, present even at zero field.

> **There is no $1/(1+\delta)$ on the kick.** In the exact Hamiltonian the
> chromatic dependence enters only through the drift's
> $p_s=\sqrt{(1+\delta)^2-p_x^2-p_y^2}$. The familiar $K_1x/(1+\delta)$ form
> belongs to the *expanded* Hamiltonian; using it together with an exact drift
> double-counts chromaticity. (The fringe maps of Section 6 *do* carry
> $1/(1+\delta)$ explicitly, because they come from integrating across the edge
> where $p_s$ appears.)

## 5. Exact drift and exact sector bend

Both are integrable and share one interface: $h$ sets the frame curvature,
$b_0=qB_0/P_0$ sets the dipole strength, and **$h\neq b_0$ is allowed**. A drift
is $b_0=0$ with $h$ free; a sector bend on its design orbit is $h=b_0$; a
straight-frame bend is $h=0$, $b_0\neq0$.

The bend vector potential and Hamiltonian are

$$
    \hat a_s=-b_0\left[x-\frac{hx^2}{2(1+hx)}\right],
    \qquad
    H=1+p_z+b_0\left(x+\frac{hx^2}{2}\right)-(1+hx)\,p_s,
$$

with $p_s=\sqrt{(1+p_z)^2-p_x^2-p_y^2}$. Setting $b_0=0$ gives the drift.

Both maps share the same structure: $p_y$ and $p_z$ are constants, $(p_x,p_s)$
rotate through $hs$, and $y$ and $z$ follow from a single shared quantity
$\Delta$ with

$$
    y=y_0+p_y\,\Delta,\qquad z=z_0+s-(1+p_z)\,\Delta,
$$

the second following from the first by $p_y\to-(1+p_z)$. For the bend,

$$
    \Delta=\frac{hs}{b_0}-\frac{1}{b_0}\left[\arcsin\frac{p_x}{w}-\arcsin\frac{p_{x,0}}{w}\right],
    \qquad w=\sqrt{(1+p_z)^2-p_y^2},
$$

and for the drift $\Delta=\dfrac{(1+hx)p_x-(1+hx_0)p_{x,0}}{h\left[(1+p_z)^2-p_y^2\right]}$.

### 5.1 Verification

The closed forms were checked numerically:

| case | $\max\lvert J^{T}SJ-S\rvert$ | vs RK4 (4·10⁵ steps) |
|---|---|---|
| drift, $h=0$ | 2.6e-23 | — |
| drift, $h=0.35$ | 3.3e-16 | 4.2e-15 |
| bend, $h=b_0=0.3$ | 1.1e-16 | 3.2e-16 |
| bend, $h\neq b_0$ | 1.1e-16 | 3.5e-15 |
| bend, $h=0$ | 3.9e-16 | 1.9e-12 |

Symplectic to machine precision, and consistent with direct integration of the
canonical equations. The $1.9\times10^{-12}$ entry is RK4 truncation, not map
error.

### 5.2 Removable singularities — an implementation requirement

Both $h\to0$ and $b_0\to0$ are removable singularities of the closed forms, and
both are numerically unusable near the limit:

- the drift's $x=\dfrac{(1+hx_0)p_{s,0}-p_s}{hp_s}$ is $0/0$ as $h\to0$;
- the bend's $x=-\dfrac1h+\dfrac{p_s}{b_0}-\dfrac{1}{b_0h}\dfrac{\mathrm dp_x}{\mathrm ds}$
  diverges term-by-term as either goes to zero.

Measured: evaluating at $h=10^{-9}$ or $b_0=10^{-9}$ reproduces the limit to
only $\sim10^{-7}$ — five to eight digits lost to cancellation. Each element
therefore needs an explicit small-parameter branch (or a $\Delta$-form rewrite
that never forms $1/h$), with the crossover chosen from the measured error, not
guessed. This is a correctness requirement, not an optimization: a lattice with
one nearly-straight bend will otherwise produce silent garbage.

### 5.3 Pole-face geometry: `ROT_XZ` and `WEDGE`

These two maps are what give a bend its pole-face angles, and therefore what
distinguishes a rectangular bend from a sector bend. They are **geometry, not
imperfections** — the angles are chosen by the magnet designer. They share
machinery with misalignments (both are Euclidean transformations), which is why
they live in PTC's `Sc_euclidean.f90`, but the role is different.

Without them: only a sector bend with faces perpendicular to the trajectory.
An RBEND *is* a sector body plus wedges at $e_1=e_2=\alpha/2$.

#### `ROT_XZ` — the field-free rotation

A rotation of the reference frame by $A$ about $\mathbf e_y$. Taking

$$
    \mathbf e_x'=\cos A\,\mathbf e_x+\sin A\,\mathbf e_s,
    \qquad
    \mathbf e_s'=-\sin A\,\mathbf e_x+\cos A\,\mathbf e_s,
$$

the momentum rotates as a vector, $p_x'=p_x\cos A+p_s\sin A$. The coordinates
are harder, because the new reference plane $s'=0$ is a *different plane in
space*: the particle must be drifted onto it. Along a field-free trajectory
$\mathbf r(s)=\bigl(x+\tfrac{p_x}{p_s}s,\;y+\tfrac{p_y}{p_s}s,\;s\bigr)$, the
condition $s'=\mathbf r\cdot\mathbf e_s'=0$ gives the crossing point

$$
    s^\ast=\frac{x\tan A}{P_T},
    \qquad
    P_T\equiv1-\frac{p_x\tan A}{p_s} .
$$

Evaluating there and projecting onto the new axes,

$$
    \boxed{\;x'=\frac{x}{\cos A\;P_T},\qquad
           p_x'=p_x\cos A+p_s\sin A,\qquad
           y'=y+\frac{p_y}{p_s}s^\ast,\qquad
           \Delta z=-\frac{(1+\delta)}{p_s}s^\ast\;}
$$

the last being minus the extra path length, since $z=s-\ell$ and the reference
does not advance during a rotation at a point.

*Verified:* reproduces PTC's `ROT_XZ` on $(x,p_x,y,p_y)$ to $2\times10^{-19}$,
and the longitudinal term to the same precision **with the opposite sign** —
the fourth independent sighting of PTC's longitudinal orientation
(Sections 2.1 and 6.4).

A useful consistency check: the curved drift of Section 5 has
$p_x=p_{x,0}\cos(hs)+p_{s,0}\sin(hs)$, which is this same rotation at $A=hs$. A
curved drift *is* a continuous sequence of frame rotations.

#### `WEDGE` — the rotation with the field on

Tilting a pole face adds or removes a wedge of dipole field. Two derivations,
which agree.

**From the vector potential.** Under the frame rotation the potential
$\hat{\mathbf a}=\hat a_s\mathbf e_s$ acquires a transverse component in the new
frame, $\hat a_{x'}=\hat a_s(\mathbf e_s\cdot\mathbf e_x')=\hat a_s\sin A$. With
the straight-frame dipole $\hat a_s=-b_1x$ (Section 4.4 at $h=0$), the *kinetic*
momentum rotates as a vector while the *canonical* one picks up the gauge term:

$$
    p_x'=\underbrace{p_x\cos A+p_s\sin A}_{\text{kinetic rotation}}
        \;\underbrace{-\,b_1x\sin A}_{\hat a_{x'}}
    =p_x\cos A+\left(p_s-b_1x\right)\sin A .
$$

So the *only* change from `ROT_XZ` in the momentum line is $p_s\to p_s-b_1x$,
which is exactly what the implementation shows.

**As a limit of the exact bend.** More powerfully, the whole map is the exact
sector bend of Section 5 in the limit

$$
    L\to0,\qquad h\to\infty,\qquad A=hL\ \text{fixed},
$$

an infinitesimally thin sliver subtending a finite angle — which is what a wedge
*is*. Every term follows. The bend's
$p_x=p_{x,0}\cos(hL)+\frac{\sin(hL)}{h}\left[-b_0(1+hx_0)+hp_{s,0}\right]$ tends
to $p_{x,0}\cos A+\sin A\,(p_{s,0}-b_0x_0)$ as $b_0/h\to0$; and the bend's
shared quantity becomes

$$
    \Delta=\frac{A+\arcsin\!\frac{p_{x,0}}{w}-\arcsin\!\frac{p_x}{w}}{b_1},
    \qquad w=\sqrt{(1+\delta)^2-p_y^2},
$$

feeding the same $y=y_0+p_y\Delta$ and $z=z_0-(1+\delta)\Delta$ as the bend.

*Verified:* the wedge map matches the exact bend at $L=A/h$ with error falling
as $1/h$ — $4.6\times10^{-5}$, $10^{-6}$, $10^{-7}$, $10^{-8}$ at
$h=10^3\ldots10^6$ — confirming the limit rather than an approximation to it.
And $b_1\to0$ recovers `ROT_XZ` with error $\propto b_1$
($1.9\times10^{-8}$ at $b_1=10^{-4}$), which the implementation also short-circuits
explicitly.

**The transverse position uses a cancellation-free form.** The bend's
$x=-\tfrac1h+\tfrac{p_s}{b_0}-\tfrac{1}{b_0h}\tfrac{\mathrm dp_x}{\mathrm ds}$
is $\infty-\infty$ in this limit, so it is rearranged to

$$
    x'=x\cos A+\frac{x\,p_x\sin2A+\sin^2\!A\left(2xp_s-b_1x^2\right)}
                    {p_s'+p_s\cos A-p_x\sin A},
    \qquad p_s'=\sqrt{(1+\delta)^2-p_x'^2-p_y^2},
$$

which is finite term by term. This is the same discipline Section 5.2 requires
of the bend itself, and it is worth copying rather than re-deriving.

Both maps are exactly symplectic — $1.4\times10^{-17}$ and $1.1\times10^{-16}$
under PTC's orientation, against $0.22$ under the other one.

**One more flag to pin:** `n_wedge`. At $0$ the closed form above is used; at
nonzero values PTC instead *integrates* the wedge with its own Yoshida
composition (`wyosh`, `wyoshik`, `wyoshid`), which gives different numbers at
finite step count. Same class of switch as `MODEL` and `METHOD`.

## 6. Fringe fields, as PTC implements them

Decoded from the PTC source shipped inside MAD-X
(`libs/ptc/src/Sh_def_kind.f90`): `MULTIPOLE_FRINGER:4492`,
`FRINGE_dipoleR:4838`, `FACER:4799`, `FRINGE2QUADR:5070`, `EDGER:5285`,
`fringe_TEAPOTr:12641`. Line numbers are for the `master` branch at the time of
writing and are given so the claims here can be re-checked, not relied on.

### 6.1 Three independent mechanisms

PTC applies up to three unrelated fringe maps at each magnet face, gated
separately:

| routine | what it models | gate |
|---|---|---|
| `EDGE` | dipole pole face: rotation, face curvature, `FINT`/`HGAP`, wedge | always, unless killed |
| `MULTIPOLE_FRINGE` | hard-edge multipole fringe (Forest–Milutinović), **all orders** | `k%FRINGE` or `permfringe∈{1,3}` |
| `FRINGE2QUAD` | soft-edge quadrupole fringe (`VA`, `VS`) | `permfringe∈{2,3}` |

They are applied in that order at the entrance and in **exactly the reversed
order** at the exit, with the charge sign flipped ($\sigma=+q$ entering,
$-q$ leaving). That is the conjugation-sandwich structure independently arrived
at for our element compilation, so PTC's layout maps onto ours without
rearrangement.

`KILL_ENT_FRINGE` / `KILL_EXI_FRINGE` disable a face entirely; `DIR` handles
reverse propagation by swapping which face is which.

### 6.2 Generic multipole hard-edge fringe

**Why a hard edge must have a fringe at all.** The hard-edge ansatz — a
two-dimensional potential $\hat a_s(x,y)$ multiplied by a step $g(s)$ — is *not*
a solution of Maxwell's equations. Writing $\hat B_y+i\hat B_x=g(s)F(w)$ with
$F$ analytic, the transverse divergence vanishes identically, but

$$
    (\nabla\times\mathbf B)_x=\partial_y\hat B_s-\partial_s\hat B_y=-g'(s)\,\Re F\neq0 .
$$

Curl-freedom therefore *forces* a longitudinal field

$$
    \hat B_s=g'(s)\,\Im\!\left[G(w)\right],\qquad G'(w)=F(w),
$$

the harmonic conjugate of the two-dimensional potential. As $g'\to\delta(s)$ the
field diverges while its integral stays finite: **the fringe is the residue of
that delta function.** It is not a refinement that can be switched off — a
magnet with no fringe violates Maxwell.

**The generator.** A nonzero $\hat B_s$ requires transverse vector-potential
components. Expanding the Hamiltonian to first order in them,

$$
    H=-\hat a_s-\sqrt{(1+\delta)^2-(p_x-\hat a_x)^2-(p_y-\hat a_y)^2}
     \;\simeq\;-\hat a_s-p_s-\frac{p_x\hat a_x+p_y\hat a_y}{p_s},
$$

and integrating across a vanishing edge, $\int\hat a_s\,\mathrm ds\to0$ and
$\int p_s\,\mathrm ds\to0$ (bounded integrands over zero length) while
$\mathcal A_{x,y}\equiv\int\hat a_{x,y}\,\mathrm ds$ survives. The fringe map is
therefore generated by

$$
    \boxed{\;f=-\frac{p_x\mathcal A_x+p_y\mathcal A_y}{p_s},\qquad p_s\to1+\delta\;}
$$

**This is what "exact in $(1+\delta)$" means** in the Forest–Milutinović title:
first order in the transverse vector potential, all orders in $(1+\delta)$.

Because $f$ is **linear in the momenta**, its flow is a *point transformation* —
the coordinates shift by functions of the coordinates alone and the momenta
follow by the inverse-transpose Jacobian. That is exactly the structure of the
implementation below, and it is why the map is exactly symplectic rather than
symplectic to some order.

**The integrated potential in closed form.** Comparing $:f:x=\partial
f/\partial p_x$ with PTC's coordinate update identifies $F_x=\mathcal A_x$ and
$F_y=\mathcal A_y$, and the loop below sums to

$$
    \boxed{\;\mathcal A_x+i\mathcal A_y=\sum_n\frac{-\sigma\,w}{4n(n+1)}
      \Big[(n+1)\,\overline{c_nw^{\,n}}-c_nw^{\,n}\Big],
      \qquad c_n=b_n+ia_n,\quad w=x+iy\;}
$$

with $\sigma=+q$ entering the magnet and $-q$ leaving.

*Verified:* the closed form agrees with PTC's loop to $9\times10^{-19}$; it
satisfies the Maxwell constraint

$$
    \partial_x\mathcal A_y-\partial_y\mathcal A_x=\frac{\sigma}{n}\,\Im\!\left[c_nw^{\,n}\right]
$$

— the integrated $\hat B_s$ — to the finite-difference floor for $n=1\ldots4$;
it reduces at $n=2$ to Forest–Milutinović; and the assembled map is symplectic
to $10^{-11}$ (also a finite-difference floor). The residual freedom
$\mathcal A\to\mathcal A+\nabla\chi$ is a gauge choice, and the form above is
PTC's.

**PTC's `BN`/`AN` arrays are 1-indexed**: `BN(1)` is the dipole, `BN(2)` the
quadrupole. This is the $b_n$ indexing of Section 4.2, *not* the 0-indexed
$K_n$ of Section 4.1 — a third convention in the same code path.

For each order $n$ up to $\min(\texttt{NMUL},\texttt{HIGHEST\_FRINGE})$,

$$
    U_n+iV_n=\frac{-\sigma}{4(n+1)}\,(b_n+ia_n)\,(x+iy)^n ,
$$

$$
    F_x=\sum_n\left[U_nx+\frac{n+2}{n}V_ny\right],
    \qquad
    F_y=\sum_n\left[U_ny-\frac{n+2}{n}V_nx\right].
$$

With $d=1/(1+\delta)$ the map is a **canonical point transformation**, exact,
not a truncated Lie exponential:

$$
    x\to x-F_xd,\qquad y\to y-F_yd,
$$
$$
    \begin{pmatrix}p_x\\p_y\end{pmatrix}\to J^{-T}\begin{pmatrix}p_x\\p_y\end{pmatrix},
    \qquad
    J=\begin{pmatrix}1-d\,\partial_xF_x & -d\,\partial_yF_x\\[2pt]
                     -d\,\partial_xF_y & 1-d\,\partial_yF_y\end{pmatrix},
$$
$$
    z\to z-\left(p_x^{\rm new}F_x+p_y^{\rm new}F_y\right)d^2 .
$$

Symplecticity is exact because $J$ is formed analytically inside the same loop
and inverted in closed form; the longitudinal term uses the **updated**
momenta. Under `TIME=TRUE` the only change is that $d$ is computed as
$1/\sqrt{1+2p_t/\beta_0+p_t^2}$ — the same number by a different route — and the
longitudinal update carries an extra $(1/\beta_0+p_t)$ factor.

**Quadrupole specialization.** Setting $b_2$ alone and expanding the sum gives

$$
    F_x=-\frac{b_2}{12}\left(x^3+3xy^2\right),
    \qquad
    F_y=+\frac{b_2}{12}\left(y^3+3x^2y\right),
$$

which is the Forest–Milutinović generator
$f_q=\frac{K_1}{12(1+\delta)}\left[-(x^3+3xy^2)p_x+(y^3+3yx^2)p_y\right]$.
The general-$n$ formula above therefore covers quadrupole through octupole and
beyond with one implementation — the same conclusion the general-multipole Core
design reached from the field side.

> **Do not double-count the dipole.** When `BEND_FRINGE` is set, the $n=1$
> **normal** component $b_1$ is excluded from this sum — only the skew $a_1$
> contributes — because `FRINGE_dipole` already handles it.

### 6.3 The dipole face has six components, not one

At the entrance of a sector bend (`fringe_TEAPOTr`, `DIR=1`, `EDGE(1)≠0`), in
order:

1. **`ROT_XZ(e)`** — an exact coordinate rotation through the pole-face
   angle (Section 5.3).
2. **`FACE(H)`** — pole-face curvature $H$ ( `H1`/`H2` ):
   $$\Delta p_x=\frac{\sigma b_1H}{2}\left(x^2-\frac{y^2}{\cos^3e}\right),
     \qquad \Delta p_y=-\frac{\sigma b_1H}{\cos^3e}\,xy .$$
3. **`FRINGE_dipole`** — the `FINT`/`HGAP` map, Section 6.3.1.
4. **`MULTIPOLE_FRINGE`** — Section 6.2.
5. **`FRINGE2QUAD`** — Section 6.4.
6. **Combined-function wedge** — the quadrupole component seen through a
   tilted face:
   $$\Delta p_x=e\,b_2\left(w_1x^2-\tfrac{w_2}{2}y^2\right),\qquad
     \Delta p_y=-e\,b_2\,w_2\,xy$$
   with `wedge_coeff` $=(w_1,w_2)$, **or**, if fringes are off and
   `MAD8_WEDGE` is set, the MAD8 form $\Delta p_x=e\,b_2(x^2-y^2)$,
   $\Delta p_y=-2e\,b_2xy$.
7. **`WEDGE(-e)`** — the exact geometric wedge (Section 5.3).

The exit repeats all seven in reverse. Steps 1, 2, 6 and 7 have no analogue in
a straight magnet; a "dipole edge" implemented as pole-face focusing alone
reproduces none of them.

#### 6.3.1 The exact `FINT`/`HGAP` map

Working in slopes $x'=p_x/p_z$, $y'=p_y/p_z$ with
$p_z=\sqrt{(1+\delta)^2-p_x^2-p_y^2}$, PTC forms a **generalized entrance
angle** that folds the fringe-field integral into the geometry,

$$
    \Phi_0=\arctan\!\left(\frac{x'}{1+y'^2}\right)
           -2b\,F G\left(1+x'^2(2+y'^2)\right)p_z ,
    \qquad F\equiv\texttt{FINT},\ G\equiv\texttt{HGAP},
$$

and then applies

$$
    y\to\frac{2y}{1+\sqrt{1-2By}},\qquad
    p_y\to p_y-b\tan(\Phi_0)\,y,\qquad
    x\to x+\tfrac12B_1y^2,\qquad
    z\to z-\tfrac12B_3y^2 ,
$$

where $B$, $B_1$, $B_3$ are contractions of $\partial\Phi_0/\partial(x',y')$
with the slope-to-momentum Jacobian.

**Why this one is implicit.** The multipole generator above is linear in the
momenta, so its flow is an explicit point transformation. The dipole fringe
instead retains the slope dependence exactly, giving a generator of the form
$f\simeq-\tfrac12\,b\tan\Phi_0(p_x,p_y,\delta)\,y^2$ — quadratic in $y$ with a
momentum-dependent coefficient. A map of that shape is naturally expressed by a
**mixed-variable generating function**, which relates old and new variables
implicitly rather than explicitly; the relation
$y_{\rm new}=y+\tfrac{B}{2}y_{\rm new}^2$ is that implicit statement. Taking its
exact root — rather than iterating or truncating — is what makes the map
symplectic to machine precision.

Two details worth copying verbatim:

- The $y$ update is the **exact** solution of the implicit relation
  $y_{\rm new}=y+\tfrac{B}{2}y_{\rm new}^2$, written in rationalized form. The
  naive root $\left(1-\sqrt{1-2By}\right)/B$ is the same number and loses
  precision as $B\to0$ — the same removable-singularity trap as Section 5.2.
- There is a **cubic term with no counterpart in most codes**, present in both
  the exact and expanded branches:
  $$\Delta p_y=-\frac{h^2y^3}{18\,F G},\qquad
    \Delta z=+\frac{h^2y^4}{72\,FG}\cdot\frac{1+\delta}{(1+\delta)^2} .$$
  It is inherited from SAD (the source comments it as such). Omitting it means
  never matching PTC on a bend with a finite gap.

#### 6.3.2 The expanded branch is a different map

With `EXACT=FALSE` PTC replaces steps 1–3 with the familiar thin forms

$$
    \Delta p_x=+\tan(e)\,\sigma b_1x,
    \qquad
    \Delta p_y=-\tan\!\left(e-\psi\right)\sigma b_1y,
    \qquad
    \psi=2\sigma FG\,b_1\frac{1+\sin^2e}{\cos e},
$$

plus the same SAD cubic. This is **not a truncation of the exact branch** — it
is a structurally different map. Benchmarks must state which one they target.

### 6.4 Soft-edge quadrupole fringe (`FRINGE2QUAD`)

Independent of everything above and gated only by `permfringe∈{2,3}`. Where
Section 6.2 models a *hard* edge — the residue of a delta function that Maxwell
forces — this one models a **soft** edge: a gradient that ramps over a finite
length rather than stepping.

**Derivation.** Write the true profile as a hard edge plus a localized
deviation, $k(s)=k_0\theta(s)+\Delta k(s)$, and perturb the transfer map about
the hard-edge solution. Near the edge $M_{\rm hard}\simeq\bigl(\begin{smallmatrix}1&s\\0&1\end{smallmatrix}\bigr)$,
so with $\delta A=\bigl(\begin{smallmatrix}0&0\\-\Delta k&0\end{smallmatrix}\bigr)$,

$$
    M_{\rm hard}^{-1}\,\delta A\,M_{\rm hard}
    =\begin{pmatrix}s\,\Delta k& s^2\Delta k\\-\Delta k&-s\,\Delta k\end{pmatrix}
    \;\Longrightarrow\;
    \int\!\mathrm ds=\begin{pmatrix}J_1&J_2\\-J_0&-J_1\end{pmatrix},
$$

with the moments $J_m=\int s^m\,\Delta k(s)\,\mathrm ds$. Defining the effective
length so that $J_0=0$ — which is what "effective length" *means* — this
exponentiates to

$$
    \boxed{\;\begin{pmatrix}x\\x'\end{pmatrix}\to
      \begin{pmatrix}e^{J_1}&J_2\\0&e^{-J_1}\end{pmatrix}
      \begin{pmatrix}x\\x'\end{pmatrix}\;}
$$

and in $y$ the gradient reverses, so $J_1\to-J_1$, $J_2\to-J_2$. That is exactly
the implemented map, and it identifies the two parameters:

$$
    f_1=J_1=\int s\,\Delta k\,\mathrm ds
    \qquad\text{(first moment, dimensionless)},
$$
$$
    f_2=J_2=\int s^2\,\Delta k\,\mathrm ds
    \qquad\text{(second moment, a length)} .
$$

**Where the $1/24$ comes from.** For a linear ramp of length $L$ centred on the
effective edge, direct integration gives $J_0=0$ and

$$
    J_1=-\frac{k_0L^2}{24},\qquad J_2=0 .
$$

Comparing with $f_1=-\sigma\,\mathcal F\lvert\mathcal F\rvert\,b/(24p_z)$ and
$k_0=b/p_z$ identifies

$$
    \boxed{\;\mathcal F=\texttt{VA}=\text{the equivalent linear-ramp length}\;}
$$

The **signed square** $\mathcal F\lvert\mathcal F\rvert$ now makes sense: $J_1$ is
a first moment and may take either sign depending on which way the profile
leans, while a length squared cannot — so the sign is carried by $\mathcal F$
itself. Squaring it instead of signed-squaring it would silently lose that.

And because $J_2$ **vanishes** for a symmetric ramp, $\mathcal G=\texttt{VS}$ is
genuinely independent: it carries profile asymmetry, not the same information at
higher order. The two parameters are not redundant.

**The skew rotation.** An order-$n$ multipole rotates at $n$ times the geometric
angle, so a quadrupole $b_2+ia_2$ is a normal quadrupole in a frame turned by
$\tfrac12\arg(b_2+ia_2)$. Hence $\alpha=-\tfrac12\arctan(a_2,b_2)$ and
$b=\lvert b_2+ia_2\rvert$: rotate to principal axes, apply the normal-quadrupole
fringe, rotate back.

**The longitudinal update is the symplectic completion.** The transverse map
depends on $\delta$ through $p_z$, so $z$ must move. Expressing the map by the
mixed-variable generating function

$$
    \tilde F=\left(e^{f_1}-1\right)xP_x+e^{f_1}\frac{f_2}{2p_z}P_x^2
            +\left(e^{-f_1}-1\right)yP_y-e^{-f_1}\frac{f_2}{2p_z}P_y^2
$$

(with $P_x,P_y$ the **new** momenta, held fixed under $\partial/\partial\delta$)
reproduces the implemented $z$ update exactly — verified to $8\times10^{-9}$,
the differencing floor. Under `TIME=TRUE` the extra `time_fac` factor is nothing
but $\mathrm d\delta/\mathrm dp_t=1/\beta$, the chain rule for the convention
change of Section 2.2.

> **Port-critical sign.** The implemented map is exactly symplectic — but with
> respect to $S_{56}=-1$, i.e. with $(z_{\rm PTC},\delta)$ conjugate in the
> *opposite* orientation to $(x,p_x)$. Measured: $1.5\times10^{-18}$ with
> $S_{56}=-1$ against $1.3\times10^{-5}$ with $S_{56}=+1$. The same holds for
> `MULTIPOLE_FRINGE` ($4\times10^{-16}$ versus $2\times10^{-7}$), so this is
> PTC's global longitudinal orientation, not a quirk of one routine.
> **An implementation using $z=s-\ell$ with the usual $S_{56}=+1$ must flip the
> sign of every longitudinal fringe update taken from this source.** Flipping it
> restores exact symplecticity under the standard $S$ (verified to the same
> $1.5\times10^{-18}$).

The implemented map, for reference:

$$
    \alpha=-\tfrac12\arctan\!\left(a_2,b_2\right),
    \qquad
    b=\sqrt{b_2^2+a_2^2},
$$
$$
    f_1=\frac{-\sigma\,\mathcal F\lvert\mathcal F\rvert\,b}{24\,p_z},
    \qquad
    f_2=\frac{\mathcal G\,b}{p_z},
$$
$$
    x\to xe^{f_1}+\frac{f_2}{p_z}p_x,\quad p_x\to p_xe^{-f_1},
    \qquad
    y\to ye^{-f_1}-\frac{f_2}{p_z}p_y,\quad p_y\to p_ye^{f_1} .
$$

The $e^{\pm f_1}$ pairing preserves $xp_x$ and $yp_y$, so the map is symplectic
by inspection.

Two traps: $\mathcal F$ and $\mathcal G$ are the element's **`VA` and `VS`**,
*not* the dipole's `FINT`/`HGAP`, despite the subroutine's argument names; and
$\mathcal F\lvert\mathcal F\rvert$ is a **signed square**, so the sign of `VA`
matters and squaring it would be wrong.

### 6.5 What a benchmark must pin

Beyond the flags in Section 7, fringe comparisons additionally require:

| symbol | why |
|---|---|
| `permfringe` (0/1/2/3) | selects which of the three mechanisms run |
| `BEND_FRINGE` | gates the dipole fringe *and* removes $b_1$ from the multipole sum |
| `HIGHEST_FRINGE` | truncates the multipole fringe sum |
| `KILL_ENT_FRINGE`, `KILL_EXI_FRINGE` | disable a face |
| `MAD8_WEDGE` | switches the combined-function wedge form; defaults `.TRUE.` |
| `wedge_coeff(1:2)` | **has no default assignment** in the sources read here; it is exposed as the settable pointer `c_%wedge_coeff`. Set it explicitly or the combined-function wedge is whatever the compiler left in memory. |
| `VA`, `VS` | soft-edge quadrupole fringe parameters |
| `FINT`, `HGAP` | per-face arrays `FINT(1:2)`, `HGAP(1:2)` — entrance and exit may differ |

`wedge_coeff` is the one to verify first against your own MAD-X build: it is a
mutable global that changes a bend's nonlinear content whenever fringes are
enabled on a combined-function magnet.

## 7. Benchmarking against PTC

PTC is the right reference: it is Forest's code, it uses convention #3 natively
under `TIME=FALSE`, and it is distributed inside MAD-X. To make agreement
meaningful the flag set must be pinned, because PTC's defaults do not match the
model above:

| flag | required | meaning |
|---|---|---|
| `TIME` | `FALSE` | convention #3, $\delta=\Delta P/P_0$ |
| `EXACT` | `TRUE` | exact Hamiltonian, **not** the expanded default |
| `MODEL` | `1` | drift-kick-drift (`2` = matrix-kick-matrix, `3` = SixTrack) |
| `METHOD` | 2 / 4 / 6 | integrator order — see the coefficients below |
| `NST` | explicit | integration steps per thick element |

`EXACT=FALSE` is the PTC default and silently selects the expanded Hamiltonian;
benchmarking against it would validate the wrong model.

**The integrator coefficients must match, not merely the order.** Per step of
`NST`, PTC composes:

| `METHOD` | structure | drifts / kicks |
|---|---|---|
| 2 | $D(\tfrac{L}{2N})\,K(\tfrac{L}{N})\,D(\tfrac{L}{2N})$ | 2 / 1 |
| 4 | $D_1K_1D_2K_2D_2K_1D_1$ | 4 / 3 |
| 6 | `YOSD(1:4)`, `YOSK(1:4)` | 8 / 7 |

with, for `METHOD=4` and $a=1-2^{1/3}$,

$$
    \text{FD1}=\frac{1}{2(1+a)}=0.675604,\quad
    \text{FD2}=a\,\text{FD1}=-0.175604,
$$
$$
    \text{FK1}=\frac{1}{1+a}=1.351207,\quad
    \text{FK2}=(a-1)\text{FK1}=-1.702414 ,
$$

i.e. Forest–Ruth/Yoshida-4. Different fourth-order compositions
(Blanes–Moan, Suzuki) agree with these only as $\texttt{NST}\to\infty$; at
finite `NST` they give different numbers, so machine-precision agreement
requires *these* coefficients. Note also that `METHOD=4` emits **4 drifts, not
6** — the merged form with shared endpoints — and that FD2 and FK2 are negative,
as any order-$>2$ splitting in $T$ and $V$ alone must be.

Two practical points for the contract:

- **Store a reference dataset, do not call MAD-X at test time.** Generate input
  coordinates plus PTC output once, commit the table, and compare against it.
  The contract then runs anywhere.
- **"Machine precision" means $\sim10^{-14}$ relative, not bitwise.** PTC and
  Octopus will order operations differently even for identical formulas. The
  exact bend's $\arcsin$ difference is the worst-conditioned step and deserves
  its own, looser, documented tolerance.

## 8. Open items

- `VA` and `VS` now have physical meaning (Section 6.4) but no measurement
  recipe: extracting them from a measured or simulated gradient profile
  $k(s)$ means evaluating $J_1$ and $J_2$ numerically, which is a small utility
  worth providing alongside the element.
- Whether $b_1$ in the multipole array may represent a bend, or whether bending
  lives only in the dipole element with an explicit $h$. Section 4.4 makes this
  concrete: $h$ and $K_0$ are independent inputs to the same potential, so a
  "bend" is $K_0\neq0$ and a curved frame is $h\neq0$, and neither implies the
  other.
- The $y$-truncation order of the curved-multipole series (Section 4.4) needs a
  measured default at the working aperture.
- Reference-energy change (ramping) makes conventions #3/#4 explicitly
  $s$-dependent through $\beta_0$; out of scope here, but it is where the
  conversion in Section 2.2 stops being a constant-coefficient map.

## References

1. E. Forest, *Beam Dynamics: A New Attitude and Framework*, Harwood Academic
   (1998); PTC as distributed with MAD-X.

2. MAD-X User's Guide, `ptc_create_layout` — `TIME`, `EXACT`, `MODEL`,
   `METHOD`, `NST`.
   <https://madx.web.cern.ch/madX/doc/usrguide/ptc_general/ptc_general.html>

3. Xsuite Physics Manual, Sections 1.5–1.6 (field expansion, conjugate
   variable table) and 1.10 (polar drift, curved exact bend).
   <https://xsuite.github.io/xsuite/docs/physics_manual/physics_man.pdf>

4. SixTrack Physics Manual — the three longitudinal translations.

5. D. Sagan, *Bmad Manual*, Section 26 — convention #4.

6. S. Y. Lee, *Accelerator Physics* — curvilinear Hamiltonian.
