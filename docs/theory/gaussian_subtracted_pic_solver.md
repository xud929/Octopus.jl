# Gaussian-Subtracted PIC Poisson Solver

This note derives a hybrid beam-beam Poisson solver that combines the analytic
soft-Gaussian (Bassetti-Erskine) field with the grid particle-in-cell (PIC)
solver. The idea is a **control variate** (a "delta-f" splitting): the smooth,
dominant Gaussian part of the source is handled *analytically* with the exact
open-boundary field, and only the small *residual* deviation from that Gaussian
is deposited on the mesh and solved with the existing zero-padded Green-function
convolution. The goal is to raise PIC field accuracy at a **fixed grid-point
count** $N_x\times N_y$ (e.g. $128\times128$), so throughput is essentially
unchanged. As in the current PIC solver, the physical box stays **adaptive** per
slice pair — only the number of mesh points is held fixed; the domain-sizing knob
of Section 6 acts on that adaptive box, not on $N_x,N_y$.

This note is a theory note. It states the decomposition, the analytic field, the
consistent grid subtraction (the cell/shape integral of a Gaussian, which needs
`erf`), the domain-sizing requirement, and the accuracy/cost argument. It does
not describe code structure; see the implementation plan in
[`todo.md`](../todo.md).

Related notes:

- [`spectral_sine_poisson_solver.md`](spectral_sine_poisson_solver.md) — the
  current Hockney/Green PIC solver conventions and the `kbb` coupling scale.
- [`beam_beam_longitudinal_kick.md`](beam_beam_longitudinal_kick.md) — the
  synchro-beam longitudinal kick reused unchanged here.

## 1. Conventions

Work in the transverse plane $\mathbf r=(x,y)$ of one directed slice-pair
interaction. The source slice has transverse charge density $\rho(\mathbf r)$
(per unit area, in macroparticle-count units), and the beam-beam potential
$\phi$ obeys the 2D Poisson equation with **open (free-space) boundary
conditions**.

Two normalizations appear in the code and must be kept apart:

- The **physical** potential solves $\nabla^2\phi=\rho$, so a unit point charge
  gives $\phi=\tfrac{1}{2\pi}\ln r$ and $\mathbf E=-\nabla\phi=-\hat{\mathbf
  r}/(2\pi r)$.
- The **PIC grid** potential is built by convolving the deposited charge with the
  integrated logarithmic Green function $G(\mathbf r)\sim-\tfrac12\ln r^2=-\ln
  r$, i.e. $\phi_{\text{PIC}}=-2\pi\phi$, so a unit deposited macroparticle gives
  $\mathbf E_{\text{PIC}}=-\nabla\phi_{\text{PIC}}=\hat{\mathbf r}/r$.

The transverse kick applied by the PIC path is

$$
    \Delta\mathbf p_\perp = 2k_{bb}\,\mathbf E_{\text{PIC}},
$$

where $k_{bb}$ is the same physical coupling used by `GaussianPoissonSolver`,
`PICPoissonSolver`, `SpectralPoissonSolver`, and `ThinStrongBeam`,

$$
    k_{bb}
    = q_1 q_2\, r_{0}\, N\, \frac{m c^2}{E_0},
$$

carried per deposited source macroparticle in the PIC path (the physical scale
divided by the source macroparticle count). The factor $2$ is fixed by the
Bassetti-Erskine convention of Section 3: a slice of $N_s$ deposited
macroparticles gives $\mathbf E_{\text{PIC}}\to N_s\hat{\mathbf r}/r$ far from
the source, while the unit-population analytic kick is $\mathbf
K_{\text{BE}}\to2\hat{\mathbf r}/r$, so

$$
    \mathbf E_{\text{PIC}} = \tfrac12 N_s\,\mathbf K_{\text{BE}}
    \quad\Longrightarrow\quad
    \Delta\mathbf p_\perp = k_{bb} N_s \mathbf K_{\text{BE}},
$$

which is exactly the soft-Gaussian solver's $k_{bb}\,w_{\text{slice}}\,\mathbf
K_{\text{BE}}$. Keeping this $\tfrac12 N_s$ (not $N_s$) is what makes the
analytic add-back of Section 8 consistent with the grid term.

## 2. The control-variate decomposition

Let $\rho_G(\mathbf r)$ be a **reference Gaussian** with the same population,
centroid, and covariance as the source slice. Split the source exactly:

$$
\boxed{\;
    \rho(\mathbf r) = \rho_G(\mathbf r) + \delta\rho(\mathbf r),
    \qquad
    \delta\rho \equiv \rho - \rho_G .
\;}
$$

Because Poisson's equation is linear, the potential and the field split the same
way,

$$
    \phi = \phi_G + \phi_\delta,
    \qquad
    \Delta\mathbf p_\perp
      = \underbrace{-\nabla\phi_G}_{\text{analytic}}
      + \underbrace{(-\nabla\phi_\delta)}_{\text{grid}} .
$$

- $\phi_G$ is the potential of the reference Gaussian. Its field is the
  **exact Bassetti-Erskine kick** (Section 3), evaluated in closed form at each
  field particle. It carries the sharp core, the full monopole, and the exact
  logarithmic open-boundary tail — precisely the parts a mesh represents poorly.
- $\phi_\delta$ is the potential of the residual $\delta\rho$, solved on the
  **existing PIC mesh** with the **same** deposition, Green-FFT convolution, and
  interpolation (Section 4). For a nearly Gaussian beam $\delta\rho$ is small and
  smooth, so the mesh only has to represent a small correction.

The residual is what is deposited; the Gaussian is what is subtracted from the
deposited grid. This is exactly the requested "deposit charge onto the PIC grid,
then subtract a Gaussian distribution from the grid."

### Reference Gaussian moments

$\rho_G$ uses the slice's measured centroid $(\mu_x,\mu_y)$ and transverse RMS
$(\sigma_x,\sigma_y)$ — the same `StrongTransverseMoments` the soft-Gaussian
solver already computes for the slice. In the uncoupled default we take an
axis-aligned Gaussian ($\sigma_{xy}=0$); the residual then absorbs any small
transverse coupling. The coupled/tilted extension is discussed in Section 7.

## 3. Analytic Gaussian field (Bassetti-Erskine)

For an axis-aligned Gaussian of unit population centered at the origin, the
open-boundary transverse field is the Bassetti-Erskine expression already
implemented as `gaussian_beambeam_kick(sigx, sigy, x, y)`, using the Faddeeva
function $w(z)=e^{-z^2}\operatorname{erfc}(-iz)$. For $\sigma_x>\sigma_y$,

$$
    K_x + i\,K_y
    = \frac{2\sqrt\pi}{\sqrt{2(\sigma_x^2-\sigma_y^2)}}
      \left[\,w\!\big(z_1\big) - e^{-\frac{x^2}{2\sigma_x^2}-\frac{y^2}{2\sigma_y^2}}\,w\!\big(z_2\big)\right],
$$

$$
    z_1=\frac{x+iy}{\sqrt{2(\sigma_x^2-\sigma_y^2)}},
    \qquad
    z_2=\frac{\tfrac{\sigma_y}{\sigma_x}x+i\tfrac{\sigma_x}{\sigma_y}y}
             {\sqrt{2(\sigma_x^2-\sigma_y^2)}},
$$

with the round-beam limit $\mathbf K = \tfrac{2}{r^2}\big(1-e^{-r^2/2\sigma^2}\big)\mathbf r$.
Evaluated at the shifted position $(x-\mu_x,\;y-\mu_y)$ and scaled by the slice
population, this is $-\nabla\phi_G$ per unit $k_{bb}$. It is exact to machine
precision — it carries no grid, no truncated tail, and no zero-mode.

## 4. The residual field on the mesh

$\delta\rho$ is formed **on the grid** as the difference of two deposited
quantities on the same nodes:

$$
    \delta Q_{ij}
    = \underbrace{Q^{\text{part}}_{ij}}_{\text{deposited particles}}
    - \underbrace{Q^{G}_{ij}}_{\text{deposited reference Gaussian}} .
$$

$Q^{\text{part}}_{ij}=\sum_p W(x_p-x_i)\,W(y_p-y_j)$ is the ordinary CIC/TSC
particle deposition. $Q^{G}_{ij}$ is the analytic deposition of $\rho_G$ under
the **same** assignment function $W$ (Section 5). The residual grid is then
convolved with the identical cached Green FFT and interpolated to the field
particles exactly as in the current PIC path.

The essential consistency requirement is that $Q^{G}$ be the *expected* particle
deposition of a truly Gaussian slice,

$$
\boxed{\;
    Q^{G}_{ij}
    = \mathbb E\!\left[Q^{\text{part}}_{ij}\right]_{\rho=\rho_G}
    = N_s\!\int\!\! \rho_G^{(1)}(\mathbf r)\,W(\mathbf r-\mathbf r_{ij})\,d^2r ,
\;}
$$

where $N_s$ is the slice population and $\rho_G^{(1)}$ is the unit-normalized
Gaussian. With this choice $\delta Q\to 0$ *in the mean* whenever the beam is
Gaussian, so the mesh carries only genuine non-Gaussian structure plus
macroparticle shot noise — the control variate is unbiased. Sampling $\rho_G$ at
node points instead (the naive choice) would leave an $O(h^2)$ shape-function
mismatch on the grid and defeat the cancellation; the shape-consistent integral
is what makes `erf` appear.

## 5. Shape-consistent Gaussian deposition (the `erf` integral)

Because both $\rho_G^{(1)}$ and the assignment function $W$ **factorize** in $x$
and $y$, the 2D node integral is a product of 1D integrals:

$$
    Q^{G}_{ij} = N_s\,g_x(x_i)\,g_y(y_j),
    \qquad
    g_x(x_i)=\int G_{\mu_x,\sigma_x}(x)\,W(x-x_i)\,dx ,
$$

with the normalized 1D Gaussian
$G_{\mu,\sigma}(x)=\tfrac{1}{\sigma\sqrt{2\pi}}e^{-(x-\mu)^2/2\sigma^2}$. The 1D
arrays $g_x$ (length $N_x$) and $g_y$ (length $N_y$) are built once per solve;
the 2D subtraction is their outer product. This is $O(N_x+N_y)$ work — cheap
next to deposition and the FFT.

### Gaussian moment integrals (node-centered)

Both assignment functions are piecewise polynomials in the node offset
$u=x-x_i$, so it is cleanest to work with **node-centered** truncated moments of
the normalized 1D Gaussian on a cell $[A,B]$,

$$
    m_k(A,B) = \int_A^B (x-x_i)^k\,G_{\mu,\sigma}(x)\,dx,\qquad k=0,1,2.
$$

Let $d_i=\mu-x_i$ (signed node-to-mean distance) and
$\Delta G\equiv G(B)-G(A)$. Using $G'(x)=-\tfrac{x-\mu}{\sigma^2}G(x)$ (so
$\int(x-\mu)G=-\sigma^2\Delta G$) and one integration by parts,

$$
\begin{aligned}
    m_0(A,B) &= \tfrac12\!\left[\operatorname{erf}\!\Big(\tfrac{B-\mu}{\sigma\sqrt2}\Big)
                               -\operatorname{erf}\!\Big(\tfrac{A-\mu}{\sigma\sqrt2}\Big)\right],\\[2pt]
    m_1(A,B) &= d_i\,m_0 - \sigma^2\,\Delta G,\\[2pt]
    m_2(A,B) &= (\sigma^2+d_i^2)\,m_0
                - \sigma^2\big[(B-\mu)G(B)-(A-\mu)G(A)\big]
                - 2 d_i\sigma^2\,\Delta G .
\end{aligned}
$$

$m_0$ is the pure `erf` term; $m_1,m_2$ add the two Gaussian point values
$G(A),G(B)$. Both CIC and TSC are fixed linear combinations of these moments over
their support cells, so each node value costs a handful of `erf`/`exp` calls.

### CIC (linear / tent) nodes

The CIC assignment is the tent $W_1(u)=\max(0,1-|u|/h)$, nonzero on the two cells
$L=[x_i-h,\,x_i]$ (where $W_1=1+u/h$) and $R=[x_i,\,x_i+h]$ (where
$W_1=1-u/h$). Hence

$$
\boxed{\;
    g(x_i) = m_0\big(x_i-h,\,x_i+h\big)
             + \frac1h\Big[m_1(L)-m_1(R)\Big].
\;}
$$

Only $m_0,m_1$ are needed. Equivalently $g$ is the Gaussian convolved with the
tent (itself the convolution of two boxcars), so it is smooth and strictly
positive.

### TSC (quadratic) nodes

The TSC assignment is the quadratic B-spline of half-width $\tfrac32 h$,

$$
    W_2(u)=
    \begin{cases}
      \tfrac34-(u/h)^2, & |u|\le\tfrac12 h,\\[2pt]
      \tfrac12\big(\tfrac32-|u|/h\big)^2, & \tfrac12 h<|u|\le\tfrac32 h,\\[2pt]
      0,&\text{otherwise,}
    \end{cases}
$$

with the three support cells

$$
    L_w=\big[x_i-\tfrac32h,\,x_i-\tfrac12h\big],\quad
    C=\big[x_i-\tfrac12h,\,x_i+\tfrac12h\big],\quad
    R_w=\big[x_i+\tfrac12h,\,x_i+\tfrac32h\big].
$$

On $C$, $W_2=\tfrac34-\tfrac{u^2}{h^2}$; on $R_w$,
$W_2=\tfrac98-\tfrac{3}{2}\tfrac uh+\tfrac12\tfrac{u^2}{h^2}$; on $L_w$,
$W_2=\tfrac98+\tfrac{3}{2}\tfrac uh+\tfrac12\tfrac{u^2}{h^2}$. Integrating term by
term against the node-centered moments gives the explicit TSC node value

$$
\boxed{
\begin{aligned}
    g(x_i) =\;&
      \tfrac34\,m_0(C) - \tfrac1{h^2}\,m_2(C)\\[2pt]
      &+\tfrac98\big[m_0(L_w)+m_0(R_w)\big]
       +\tfrac{3}{2h}\big[m_1(L_w)-m_1(R_w)\big]
       +\tfrac1{2h^2}\big[m_2(L_w)+m_2(R_w)\big].
\end{aligned}
}
$$

TSC additionally needs $m_2$. As a check, letting $\sigma\to0$ with the mean at a
node ($d_i=0$) gives $m_0(C)\to1$, $m_2\to0$, and $m_0(L_w),m_0(R_w)\to0$, so
$g\to\tfrac34$ at that node and $\tfrac18$ at each neighbor — exactly the discrete
TSC weights $(\tfrac18,\tfrac34,\tfrac18)$. The particle deposition and the
subtracted-Gaussian deposition must use the **same** method (CIC with CIC, TSC
with TSC) for the control-variate cancellation to hold.

## 6. Domain sizing: why the box must be *slightly larger*

This is the central practical constraint. It concerns the **adaptive physical
box**, not the mesh-point count: $N_x\times N_y$ stays fixed (so the FFT cost is
unchanged), while the box is grown by a user margin. The residual field solve
uses the Hockney open-boundary kernel, which returns the exact free-space field
of **whatever net charge sits on the grid**. Charge conservation therefore
governs the accuracy.

The two knobs below are exposed as `GaussianPICPoissonSolver` options
(`margin_sigma` for the box margin, `neutralize` for discrete neutralization),
each with an "off" setting so the behavior is user-controlled. (The hybrid is a
separate solver type composing a `PICPoissonSolver`, not a mode of it, so the
option names carry no `gaussian_subtract_` prefix.)

The deposited particles always sum to the full slice population,
$\sum_{ij}Q^{\text{part}}_{ij}=N_s$ (assignment functions are a partition of
unity). The subtracted Gaussian, however, only captures the mass **inside the
grid**:

$$
    \sum_{ij}Q^{G}_{ij}
    = N_s\Big(\textstyle\sum_i g_x(x_i)\Big)\Big(\sum_j g_y(y_j)\Big)
    = N_s\,(1-\varepsilon_x)(1-\varepsilon_y),
$$

where $\varepsilon$ is the fraction of the reference Gaussian lying outside the
box. For a box spanning $\pm m\sigma$ about the centroid,

$$
    \varepsilon \;\approx\; \operatorname{erfc}\!\big(m/\sqrt2\big).
$$

Hence the residual carries a **spurious net charge**

$$
    q_{\text{res}} \approx N_s(\varepsilon_x+\varepsilon_y),
$$

which the open-boundary solve turns into a spurious monopole field
$\delta\mathbf E \approx 2k_{bb}\,q_{\text{res}}\,\hat{\mathbf r}/r$ — a
long-range $1/r$ error that contaminates the field even near the core at the
relative level $q_{\text{res}}/N_s$. Keeping it below a tolerance $\tau$ requires

$$
\boxed{\;
    \varepsilon \lesssim \tau
    \quad\Longleftrightarrow\quad
    m \gtrsim \sqrt2\,\operatorname{erfc}^{-1}(\tau).
\;}
$$

| box half-width $m$ ($\sigma$) | 3 | 4 | 5 | 6 |
| --- | ---: | ---: | ---: | ---: |
| leaked mass $\varepsilon=\operatorname{erfc}(m/\sqrt2)$ | $2.7\times10^{-3}$ | $6.3\times10^{-5}$ | $5.7\times10^{-7}$ | $2.0\times10^{-9}$ |

Contrast with pure PIC, where the particle cloud is compactly supported and a
box that tightly wraps the particles is fine. Here the *subtracted Gaussian* has
exponential tails that extend beyond the particle cloud, so the box must contain
**both**. The requirement is:

- **Do not shrink the box inside the particle extent**, and size it to at least
  $m\approx5$–$6\,\sigma$ about the slice centroid so the subtracted Gaussian is
  contained to $\lesssim10^{-6}$. This is `margin_sigma` ($=m$; default 5).
- If the beam is sampled with a small cutoff (e.g. particles only reach
  $3\sigma$), the current PIC box would wrap them at $3\sigma$ and leak
  $\sim3\times10^{-3}$ of the Gaussian; the box must then be **enlarged beyond
  the particle extrema** to half-width
  $\max(\text{particle extent},\,m\sigma)$. This is the
  "slightly larger, not closely attached to the source domain" knob. Setting
  the margin to $0$ (off) recovers the ordinary particle-wrapping box.

**Discrete neutralization (robust safeguard).** The monopole error can be
removed exactly, independent of $m$, by renormalizing the subtracted grid so its
sum matches the deposited particles,

$$
    \tilde Q^{G}_{ij}
    = Q^{G}_{ij}\,\frac{\sum_{kl}Q^{\text{part}}_{kl}}{\sum_{kl}Q^{G}_{kl}},
$$

which forces $\sum_{ij}\delta Q_{ij}=0$ and kills the spurious monopole. This is
the `neutralize` flag (default `true`); with it on, the method tolerates a
tighter box and the margin only controls the residual's *dipole and higher*
leakage, which is far weaker. With it off, accuracy relies on the margin alone.
A modest margin plus neutralization is the recommended default.

## 7. Coupled (tilted) slices and the coupling switch

The separable `erf` integral of Section 5 assumes an axis-aligned Gaussian. A
tilted slice ($\sigma_{xy}\neq0$) is not separable in the axis-aligned grid
coordinates. The natural, scale-free control variable is the transverse
**correlation coefficient**

$$
    r_{xy} = \frac{\sigma_{xy}}{\sigma_x\,\sigma_y}\in[-1,1].
$$

`coupling_tol` ($=r_{\text{tol}}$) branches on $|r_{xy}|$: at or below the
threshold the axis-aligned subtraction of Section 5 is used and the residual grid
absorbs the small coupling; above it the coupled construction below is used.
`coupling_tol = Inf` (the default) always takes the uncoupled path.

### 7.1 Analytic part: exact at any tilt

The analytic add-back needs no approximation. Diagonalise
$A=\begin{pmatrix}a&b\\b&d\end{pmatrix}$ with
$D=\sqrt{(a-d)^2+4b^2}$, $\lambda_{1,2}=(a+d\pm D)/2$,
$\theta=\tfrac12\operatorname{atan2}(2b,\,a-d)$; rotate the relative coordinate
into the principal frame, evaluate Bassetti-Erskine with
$(\sqrt{\lambda_1},\sqrt{\lambda_2})$, and rotate the kick back. The longitudinal
term must additionally carry the rotation derivative $\theta_u$ of
[`beam_beam_longitudinal_kick.md`](beam_beam_longitudinal_kick.md) Section 5 —
keeping only the transported eigenvalues is *not* equivalent.

The implementation therefore delegates the whole analytic part to the
soft-Gaussian `_cp_covariance_kick` on the coupled `StrongTransverseMoments`,
which already implements the rotated kick together with the $\lambda_{1,u}$,
$\lambda_{2,u}$ and $\theta_u$ contributions. Nothing new is derived here, and
the coupled analytic field is exact to machine precision at any tilt.

### 7.2 Gridded part: the conditional expansion

Only the *deposited* reference Gaussian $Q^G$ needs work, because a tilted
Gaussian is not a product of an $x$-function and a $y$-function. It is, however,
separable **conditionally**:

$$
\boxed{\;
  \rho_G(x,y) = G(x;\mu_x,\sigma_x)\;G\big(y;\;m(x),\,s\big),\qquad
  m(x)=\mu_y+\lambda\,(x-\mu_x),\quad
  \lambda=\frac{\sigma_{xy}}{\sigma_x^{2}},\quad
  s^{2}=\sigma_y^{2}-\frac{\sigma_{xy}^{2}}{\sigma_x^{2}} .
\;}
$$

The conditional variance $s^2$ is **exact**, not expanded. Substituting into the
shape-consistency requirement of Section 4 and using the separability of the
assignment function $W$,

$$
    \frac{Q^{G}_{ij}}{N_s}
    = \int\!dx\;G(x;\mu_x,\sigma_x)\,W(x-x_i)\;
      g\big(y_j;\,m(x),\,s\big),
    \qquad
    g(y_j;\mu,s)=\int\!dy\,G(y;\mu,s)\,W(y-y_j).
$$

The only obstruction to separability is that the inner profile is evaluated at an
$x$-dependent mean. Expanding $g$ in that mean shift about $\mu_y$, with
$u=x-\mu_x$,

$$
    g\big(y_j;\mu_y+\lambda u,s\big)
      = g_j + \lambda u\,g'_j + \tfrac12\lambda^2u^2\,g''_j + O(\lambda^3u^3),
    \qquad g'=\frac{\partial g}{\partial\mu},\;\;g''=\frac{\partial^2g}{\partial\mu^2},
$$

gives **three separable outer products**:

$$
\boxed{\;
    \frac{Q^{G}_{ij}}{N_s}
    = M^{(0)}_i\,g_j
    \;+\;\lambda\,M^{(1)}_i\,g'_j
    \;+\;\tfrac12\lambda^{2}\,M^{(2)}_i\,g''_j
    \;+\;O(\lambda^{3}),
\;}
\qquad
M^{(k)}_i=\int (x-\mu_x)^k\,G\,W(x-x_i)\,dx .
$$

The cost is therefore $O(N_x+N_y)$ to build and $O(N_xN_y)$ to subtract — the
same order as the uncoupled path, with no 2D quadrature anywhere.

### 7.3 Numerical rank and the ordinary-PIC fallback

The conditional representation exists only for a positive-definite covariance.
Writing

$$
  \eta = \frac{s^2}{\sigma_y^2} = 1-r_{xy}^2,
$$

shows why checking only $\sigma_x>0$ and $\sigma_y>0$ is insufficient: a line
distribution can have two positive marginal RMS values while $\eta=0$. In
floating-point arithmetic, evaluating $\eta$ has an absolute uncertainty of
order $\epsilon$, and its relative uncertainty is therefore
$O(\epsilon/\eta)$. The implementation requires

$$
\boxed{\eta > \sqrt{\epsilon}},
$$

which limits the conditional-variance relative uncertainty to
$O(\sqrt{\epsilon})$. The test uses a fused multiply-add for
$1-r_{xy}^{2}$ where the hardware and numeric type provide one. Equivalently,
the accepted conditional RMS satisfies
$s/\sigma_y>\epsilon^{1/4}$: approximately $1.22\times10^{-4}$ for `Float64`
and $1.86\times10^{-2}$ for `Float32`.

When a coupled reference fails this dimensionless rank test, or when either
marginal RMS is zero or non-finite, the whole directed slice interaction uses
the embedded ordinary-PIC algorithm. Subtracting an artificial narrow Gaussian
would put unresolved high-frequency structure on the grid and then add back a
singular analytic field; ordinary PIC is the well-defined limiting algorithm.
The fallback uses no physical length threshold, is identical on CPU and CUDA,
and leaves well-conditioned GaussianPIC interactions unchanged.

### 7.4 The two ingredients in closed form

**Assignment-weighted moments $M^{(k)}$.** Work with central moments of the
normalised 1D Gaussian on a cell $[A,B]$,
$c_k=\int_A^B (x-\mu)^k G\,dx$. One integration by parts using
$(x-\mu)G=-\sigma^2G'$ gives the recursion

$$
\boxed{\;
    c_k = -\sigma^{2}\Big[(x-\mu)^{k-1}G\Big]_A^B
          + (k-1)\,\sigma^{2}\,c_{k-2},
\;}
\qquad
c_0=\tfrac12\!\left[\operatorname{erf}\tfrac{B-\mu}{\sigma\sqrt2}-\operatorname{erf}\tfrac{A-\mu}{\sigma\sqrt2}\right],
\quad c_1=-\sigma^2\Delta G,
$$

which yields $c_0\ldots c_4$ from two `erf` and two `exp` evaluations per cell.
Node-centred moments follow by the binomial shift with $d=\mu-x_i$, and the
assignment-weighted $W_k=\int (x-x_i)^kGW$ are fixed linear combinations of them
over the support cells — for CIC,
$W_k = m_k(L)+m_{k+1}(L)/h + m_k(R)-m_{k+1}(R)/h$, and analogously for TSC with
the quadratic weights of Section 5. Finally
$M^{(1)}=W_1-dW_0$ and $M^{(2)}=W_2-2dW_1+d^2W_0$.

**Mean-derivatives $g'$, $g''$.** Since $\partial G/\partial\mu=-\partial G/\partial y$,
integrating by parts moves the derivative onto the assignment function:

$$
\boxed{\;
    g'=\int G\,W'\,dy,
    \qquad
    g''=\int G\,W''\,dy .
\;}
$$

For CIC, $W'=\pm1/h$ on the two support cells and $W''$ is the distribution
$\tfrac1h[\delta(u+h)-2\delta(u)+\delta(u-h)]$, so

$$
    g'_j=\frac{m_0(L_j)-m_0(R_j)}{h},
    \qquad
    g''_j=\frac{G(y_j-h)-2G(y_j)+G(y_j+h)}{h}.
$$

For TSC, $W_2'=-2u/h^2$ on the core and $\mp(\tfrac32\mp u/h)/h$ on the wings,
while $W_2''=-2/h^2$ on the core and $+1/h^2$ on each wing, giving $g'$ as a
combination of $c_0,c_1$ per cell and $g''$ as a pure `erf` difference. Both are
closed form; no quadrature is used.

### 7.5 Validity, and where it must not be used

The expansion is truncated at second order. Writing the $\lambda^2$ term relative
to the leading one,

$$
    \frac{\tfrac12\lambda^2M^{(2)}g''}{M^{(0)}g}
    \;\sim\;
    \tfrac12\,\frac{\lambda^2\sigma_x^2}{s^2}
    \;=\;\frac{1}{2}\frac{r_{xy}^{2}}{1-r_{xy}^{2}} ,
$$

so **the expansion parameter is the correlation itself**, not $\lambda$: it is
$0.005$ at $r_{xy}=0.1$, $0.05$ at $0.3$, and $0.28$ at $0.6$, where truncation is
no longer small.

Measured against brute-force 2D quadrature of the tilted Gaussian against the same
assignment function (worst relative node error; "uncoupled" is the axis-aligned
formula of Section 5):

| $r_{xy}$ | uncoupled | coupled (CIC) | coupled (TSC) |
| ---: | ---: | ---: | ---: |
| 0.05 | 8.9e-2 | **7.7e-5** | **7.2e-5** |
| 0.20 | 4.8e-1 | **4.6e-3** | **4.4e-3** |
| 0.50 | 3.3e0 | 1.2e-1 | 1.1e-1 |

**The consequence for the total field is aspect-ratio dependent, and the coupled
branch is not universally better.** Measured end to end against the exact rotated
Bassetti-Erskine field (median relative kick error, grid 128):

| beams | $r_{xy}$ | uncoupled | coupled | gain |
| --- | ---: | ---: | ---: | ---: |
| 11:1 (production) | 0.1 | 2.6e-3 | 1.7e-3 | 1.53x |
| 11:1 | 0.3 | 5.8e-3 | 2.0e-3 | **2.95x** |
| 11:1 | 0.6 | 1.4e-2 | 8.6e-3 | 1.65x |
| 2:1 | 0.1 | 1.9e-3 | 1.9e-3 | 1.00x |
| 2:1 | 0.3 | 2.0e-3 | 2.8e-3 | 0.71x |
| 2:1 | 0.6 | 2.2e-3 | 2.1e-2 | **0.10x** |

For flat beams — the regime the hybrid targets — the coupled branch wins across
the whole range. For near-round beams the *uncoupled* baseline is already at the
grid floor, so the $O(r^3)$ truncation dominates and the coupled branch can be
worse. **Recommended use: flat beams with $r_{\text{tol}}\sim0.05$-$0.1$.** Do not
enable it for near-round slices with strong tilt.

The two CUDA *reference* routes raise rather than silently running the
uncoupled subtraction; the default CUDA indexed-wavefront route implements
the coupled subtraction (this paragraph once said the branch was CPU-only —
corrected by the 2026-08-05 audit, U8-1; the solver docstring was already
right).

## 8. Longitudinal kick and the drift-to-boundary structure

The strong-strong PIC path drifts the source slice to the **left and right
longitudinal boundaries** of the field slice, solves the field at each boundary,
and interpolates in $z$; with `longitudinal_kick=true` it also applies the
potential-difference $p_z$ kick and the virtual-drift $p_z$ terms of the Hirata
map. The hybrid preserves this structure exactly:

- At each boundary the reference Gaussian is the source slice's moments
  **transported by the linear drift** $s$ to that boundary,
  $\mu\to\mu+\mu'\!s$ and $\Sigma\to\Sigma + s(\dots) + s^2(\dots)$ — the same
  transport the soft-Gaussian solver already uses for its per-particle drifted
  source moments. The subtraction $Q^{G}$ and the analytic Bassetti-Erskine
  field both use these drifted moments, so the analytic and residual parts share
  one geometry.
- **Transverse kick.** By linearity, using the $\mathbf E_{\text{PIC}}=\tfrac12
  N_s\mathbf K_{\text{BE}}$ correspondence of Section 1,

$$
    \Delta\mathbf p_\perp(\mathbf r)
    = 2k_{bb}\Big[\,\tfrac12 N_s\,\mathbf K_{\text{BE}}(\sigma',\mathbf r-\mu')
       \;+\; \mathbf E_\delta(\mathbf r)\,\Big],
$$

  where $\mathbf K_{\text{BE}}$ is the unit-population analytic field of
  Section 3 and $\mathbf E_\delta$ is the interpolated residual grid field in the
  same $\phi_{\text{PIC}}$ normalization. The $\tfrac12$ is **not** a free
  constant: it is required for the analytic term to carry the same physical
  weight as the grid term it replaces (Section 1), and it is what the
  pure-Gaussian limit of Section 10 checks.

- **Longitudinal kick.** The $p_z$ kick is linear in the potential,
  $\phi=\phi_G+\phi_\delta$, so it splits into the analytic soft-Gaussian
  synchro-beam $p_z$ term (the moment-based formula of
  `beam_beam_longitudinal_kick.md`, using the drifted Gaussian moments) plus the
  residual potential-difference term $\phi_{\delta,L}-\phi_{\delta,R}$ read from
  the residual grid exactly as the current PIC path does. No new longitudinal
  physics is introduced; both pieces already exist.

## 9. Why accuracy improves without costing speed

**Accuracy.** A grid Poisson solve has an error roughly proportional to the
*magnitude and curvature of the field it must represent* (deposition smoothing,
finite-difference gradients, and boundary truncation all scale with the local
field). The dominant, sharply peaked Gaussian core is the hardest part for the
mesh. Moving it into the exact analytic term leaves the grid representing only
$\delta\rho$, whose amplitude is the ratio
$\lVert\delta\rho\rVert/\lVert\rho\rVert$ smaller than the full source, so the
grid-induced field error falls by roughly the same factor at the **same mesh**.
The exact core and the exact $-\tfrac{q}{2\pi}\ln r$ open-boundary tail come from
Bassetti-Erskine, removing PIC's two largest error sources (core discretization
and tail truncation) simultaneously.

*Measured* (`validation/gaussian_pic_field_validation.jl`, deterministic Gaussian
quantile source vs. the exact Bassetti-Erskine field, CIC, normalized median /
max transverse-kick error over a $\pm4\sigma$ grid):

| aspect ratio | grid | PIC median | hybrid median | median gain |
| --- | ---: | ---: | ---: | ---: |
| round | 48 | 1.5e-3 | 1.6e-4 | 9.1x |
| round | 128 | 4.6e-4 | 1.8e-4 | 2.6x |
| ~11:1 (production e-) | 48 | 4.5e-3 | 2.2e-4 | 20.6x |
| ~11:1 (production e-) | 128 | 1.3e-3 | 3.2e-4 | 4.1x |
| 25:1 | 48 | 5.0e-3 | 2.8e-4 | 17.6x |

> **What the hybrid column measures (2026-08-06, audit lead U23-2).** These
> numbers are unchanged, but until now they could not have been wrong. The
> script forced both the subtracted profile and the added-back field to the
> *nominal* $(0, \sigma)$, and the add-back was the identical
> `gaussian_beambeam_kick` call supplying the reference, so the reported hybrid
> error reduced algebraically to $2\,\delta E/n_s$ — the magnitude of the
> residual grid field measured against zero. It carried no information about
> the Bassetti-Erskine evaluator, the moment estimate, or the consistency
> between what is subtracted and what is added back, which is exactly where a
> production bug would live: `_gpic_interaction!` derives both from
> `_gpic_source_moments`, not from nominal values.
>
> Both are now derived from the source sample's own moments, as production does.
> The measured values above reproduce to two significant figures, because a
> well-sampled symmetric source has sample moments close to nominal — but the
> column can now fail: injecting a 2% mismatch between the added-back $\sigma$
> and the subtracted one moves the round/48 hybrid median from $1.6\times
> 10^{-4}$ to $2.4\times10^{-3}$ and turns the $9.2\times$ gain into $0.6\times$,
> i.e. the hybrid reads worse than plain PIC. Under the previous form that
> injection was not representable at all.

The hybrid error is nearly **grid-independent** (~2e-4 median at every grid),
because the analytic term carries the sharp core exactly and the residual is
smooth. The practical consequence: **the hybrid at grid $48\times48$ matches or
beats plain PIC at $128\times128$** — a coarser, faster mesh at equal or better
systematic accuracy.

**Non-Gaussian sources (the fair test).** A single-Gaussian source flatters the
method, because the hybrid subtracts exactly that Gaussian. The honest test uses
a **bi-Gaussian** source — a dominant Gaussian plus an offset perturbation
Gaussian — which has an exact analytic field by superposition
($f_1\mathbf K_{\text{BE}}(\sigma_1,\mathbf r-\mu_1)+f_2\mathbf
K_{\text{BE}}(\sigma_2,\mathbf r-\mu_2)$) while the hybrid can only subtract a
*single* Gaussian fitted to the combined moments, so the perturbation lands in
the grid residual (`validation/gaussian_pic_bigaussian_validation.jl`, grid 128):

| source | PIC median | hybrid median | gain |
| --- | ---: | ---: | ---: |
| single Gaussian | 4.7e-4 | 1.8e-4 | 2.6x |
| +20% perturbation, offset $(1.5,0)\sigma$ | 5.5e-4 | 2.6e-4 | 2.2x |
| +30% narrow perturbation, $(1.5,0)\sigma$ | 3.3e-4 | 1.9e-4 | 1.8x |
| +20% perturbation, offset $(2,2)\sigma$ (coupled) | 6.5e-4 | 4.4e-4 | 1.5x |
| +10% far perturbation, $(3,0)\sigma$ | 6.1e-4 | 4.5e-4 | 1.4x |

The hybrid is **never worse than PIC** and degrades *gracefully*: the gain is
largest (2–3x) for near-Gaussian sources — the physically relevant beam-beam
regime — and shrinks toward parity as the source departs from Gaussian. The
weakest case is a *diagonally* offset perturbation, which induces x–y coupling
($\sigma_{xy}\neq0$) the uncoupled subtraction leaves in the residual; an x-only
offset (no coupling) keeps a 2.2–3.4x gain. This is exactly the regime the
coupled (rotated) subtraction of Section 7 would recover.

**Shot-noise caveat (important).** The gains above are in the *systematic*
(coherent) field — the deterministic grid-discretization bias, which is the part
that drives tune shift, luminosity, and multi-turn dynamics. In a live
simulation the *single-turn per-macroparticle* kick additionally carries
Poisson shot noise, which is **identical** for PIC and the hybrid (same particles,
same deposition) and is **not** removed by subtracting a smooth Gaussian. So the
per-particle single-turn kick RMS improves only modestly at production
statistics (the shot-noise floor dominates), while the coherent field — which
averages out shot noise and accumulates the systematic bias over many turns — is
where the large, physically meaningful gain lives.

**Cost.** The grid, the deposition, and the FFT convolution — the throughput
drivers, and the whole cost on GPU — are unchanged. The added work is:

- the separable Gaussian subtraction $g_x,g_y$: $O(N_x+N_y)$ `erf`/`exp`
  evaluations per solve, plus an $O(N_xN_y)$ outer-product subtract, negligible
  beside the FFT;
- two Bassetti-Erskine (`faddeeva_w`) evaluations per field particle (one per
  longitudinal boundary), the same per-particle cost the soft-Gaussian solver
  already pays.

**Measured CPU cost (corrected 2026-07-24).** The earlier claim that the analytic
add-back is "comparable to the grid interpolation it runs alongside" is wrong on
CPU by an order of magnitude. Measured at the production case (2.56M e- /
1.024M p, 15 slices, 8 threads), per directed slice-pair interaction:

| term | time |
| --- | ---: |
| erf profile build $g_x,g_y$ | 2.8e-5 s |
| grid subtraction $\text{amp}\cdot g_x\otimes g_y$ | 1.1e-5 s |
| slice moments | 3.2e-4 s |
| **Bassetti-Erskine add-back (2 per field particle)** | **2.68e-2 s** |
| (comparison) PIC field interpolation + kick | 2.4e-3 s |
| (comparison) whole PIC(128,128) interaction | 2.5e-2 s |

The two $O(N_x{+}N_y)$ and $O(N_xN_y)$ terms are indeed negligible as claimed,
but the per-particle `faddeeva_w` add-back is ~11x the grid interpolation and
roughly **doubles** the CPU cost of the interaction. The FFT/grid scale is
untouched, so the hybrid's speed argument survives only in the form "coarser mesh
at equal accuracy": the hybrid at $64\times64$ matches or beats PIC at
$128\times128$ systematically, and that is where the net win comes from. On CUDA
the `faddeeva_w` evaluation is fused into the existing kick kernel and the
measured penalty is much smaller (see the optimization history).

## 10. Correctness and limiting cases

- **Pure-Gaussian limit.** For a Gaussian source with the reference moments,
  $\delta\rho\to0$ in the mean and the hybrid kick reduces to the analytic
  Bassetti-Erskine kick. Requiring the hybrid to reproduce
  `GaussianPoissonSolver` on a Gaussian slice pins the overall normalization
  constant and is the first regression test.
- **Zero-subtraction limit.** With the reference population set to zero (no
  subtraction, no analytic add-back) the solver is bit-identical to the current
  PIC path — a clean A/B baseline.
- **Charge neutrality.** With discrete neutralization (Section 6),
  $\sum_{ij}\delta Q_{ij}=0$ exactly, so the residual field carries no spurious
  monopole; check that the far-field residual decays faster than $1/r$.
- **Field vs. Bassetti-Erskine.** On deterministic Gaussian macroparticles the
  hybrid field must match `gaussian_beambeam_kick` to a much smaller normalized
  error than pure PIC at the same grid, across round and flat aspect ratios
  (the existing `validation/pic_gaussian_field_validation.jl` metric).
- **Linearity.** $\phi_G+\phi_\delta$ solves the same Poisson equation as
  $\phi$; the decomposition introduces no approximation beyond the reference
  choice and the grid solve of $\delta\rho$.

## 11. Interaction with the Green-function cache

The Gaussian subtraction is **orthogonal to the Green function**, so the existing
slice-pair Green FFT cache (`green_cache=:slice_pair`) is reused **unchanged**.
The Green kernel depends only on the grid geometry (source/field box origins,
spacing, and $N_x\times N_y$) — never on the deposited charge. The hybrid changes
only *what* is convolved ($\delta Q$ instead of $Q$), not the kernel, so the same
cached $\widehat G$ multiplies the residual spectrum. Both the left- and
right-boundary residual solves of a slice pair share the one cached Green FFT,
exactly as they do now.

There is a mild synergy. The margin of Section 6 sizes the adaptive box to the
slice RMS $\sigma$ (smooth, slowly varying) rather than to the fluctuating
particle extrema. A box that tracks $\sigma$ is more stable turn to turn, so the
cached grid geometry changes less often and the slice-pair cache **hit rate can
improve**. The margin and neutralization options therefore add no Green work and
may reduce cache rebuilds. The cache's `slice_pair_green_min_ratio` /
`slice_pair_green_growth` controls apply as before.

## References

1. M. Bassetti and G. A. Erskine, "Closed expression for the electrical field of
   a two-dimensional Gaussian charge," CERN-ISR-TH-80-06 (1980).
2. R. W. Hockney and J. W. Eastwood, *Computer Simulation Using Particles*,
   McGraw-Hill (1981). Free-space FFT Poisson solve and shape-function
   deposition.
3. S. E. Parker and W. W. Lee, "A fully nonlinear characteristic method for
   gyrokinetic simulation," *Phys. Fluids B* 5 (1993) 77 — the delta-f
   control-variate idea for particle methods.
4. J. Qiang, M. A. Furman, and R. D. Ryne, "A parallel particle-in-cell model
   for beam-beam interaction in high energy ring colliders," *J. Comput. Phys.*
   198 (2004) 278.
