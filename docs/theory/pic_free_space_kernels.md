# PIC Free-Space Kernels and the On-Mesh Field Gradient

Two derivations behind `PICPoissonSolver`'s field solve: the finite-difference
stencils that turn the mesh potential into the field (`field_derivative`), and
the free-space convolution kernels that produce that potential (`green_type`,
plus the Vico-Greengard-Ferrando alternative that was evaluated and rejected).

Companion notes:
[`gaussian_subtracted_pic_solver.md`](gaussian_subtracted_pic_solver.md) for the
control-variate hybrid built on this solver, and
[`spectral_sine_poisson_solver.md`](spectral_sine_poisson_solver.md) for the
Dirichlet-box alternative.

## 1. Conventions

The grid potential is built by convolving the deposited charge with

$$
    G_{\text{PIC}}(\mathbf r) = -\tfrac12\ln r^2 = -\ln r
    \;=\; -2\pi\,G_{\text{phys}},
    \qquad
    G_{\text{phys}} = \frac{\ln r}{2\pi},\quad \nabla^2G_{\text{phys}}=\delta .
$$

A single deposited macroparticle therefore gives
$\mathbf E_{\text{PIC}}=-\nabla\phi_{\text{PIC}}=\hat{\mathbf r}/r$, and the kick
is $\Delta\mathbf p_\perp = 2k_{bb}\mathbf E_{\text{PIC}}$, which reproduces the
Bassetti-Erskine convention $\mathbf K_{\text{BE}}\to2\hat{\mathbf r}/r$ per unit
population (Section 1 of the hybrid note).

## 2. On-mesh field gradient

`_pic_field!` forms $\mathbf E=-\nabla\phi$ on the mesh. Two stencils are
available through `field_derivative`.

### 2.1 Second order (`:second`, default)

$$
    E_x\big|_i = \frac{\phi_{i-1}-\phi_{i+1}}{2h}
               = -\frac{\partial\phi}{\partial x} - \frac{h^2}{6}\frac{\partial^3\phi}{\partial x^3} + O(h^4).
$$

### 2.2 Fourth order (`:fourth`)

From the standard five-point first-derivative weights
$\tfrac{1}{12h}(1,-8,0,8,-1)$,

$$
\boxed{\;
    E_x\big|_i
      = \frac{\big(\phi_{i+2}-\phi_{i-2}\big) + 8\big(\phi_{i-1}-\phi_{i+1}\big)}{12h}
      = -\frac{\partial\phi}{\partial x} + \frac{h^4}{30}\frac{\partial^5\phi}{\partial x^5} + O(h^6).
\;}
$$

Verified on an analytic test function: the second-order stencil reduces its error
by $4\times$ per halving of $h$ and the fourth-order one by $16\times$, as the
orders require.

The wider stencil needs two neighbours, so the implementation falls back to the
second-order central form on the first ring inside the boundary and keeps the
existing one-sided formulas on the boundary itself. The adaptive box already pads
$\sim1.5$ cells beyond the particles, so the fallback rings lie outside the region
carrying the physics.

**What it buys, and what it does not.** The gradient is only one of three
second-order error sources; CIC deposition and interpolation are the others.
Measured median field error against Bassetti-Erskine (round beam, $\pm2\sigma$,
deterministic source):

| grid | `:second` | `:fourth` | gain |
| --- | ---: | ---: | ---: |
| 64² | 3.03e-3 | 1.83e-3 | 1.65x |
| 128² | 7.50e-4 | 4.66e-4 | 1.61x |
| 256² | 2.03e-4 | 1.69e-4 | 1.20x |

The gain is ~1.6x rather than the naive $O(h^2)\!\to\!O(h^4)$ factor precisely
because the other two terms remain second order. It removes *systematic*
truncation error only, and therefore does **not** reduce multi-turn emittance
growth, which is shot-noise driven.

## 3. Free-space convolution kernels

### 3.1 Node-sampled (`green_type=:standard`)

$G$ evaluated at node separations, $G_{ij}=-\tfrac12\ln r_{ij}^2$, with the
singular self-term floored. Cheapest to build and adequate for round beams, but
it samples a function with a logarithmic singularity, so its accuracy degrades as
cells become anisotropic.

### 3.2 Cell-integrated (`green_type=:integrated`, default)

The kernel is averaged over the source cell rather than sampled,

$$
    G_{ij} = \frac{-1}{2h_xh_y}\!\!\iint_{\text{cell}}\!\!\ln r^2\,dx\,dy ,
$$

evaluated from the closed-form antiderivative

$$
    \mathcal I(x,y) = \big(\ln r^2-3\big)xy + x^2\arctan\frac{y}{x} + y^2\arctan\frac{x}{y}
$$

by the four-corner difference. This removes the sampling error at the singular
cell and is what makes the kernel usable for flat beams.

**Measured kernel sensitivity** (ratio of `:standard` to `:integrated` median
field error; 1.00 means the kernel is irrelevant):

| aspect ratio | 48² | 64² | 128² | 256² |
| --- | ---: | ---: | ---: | ---: |
| round | 0.98x | 0.97x | **1.00x** | 0.98x |
| 5:1 | 0.98x | 0.99x | 1.08x | 1.18x |
| 11:1 | 1.18x | 1.20x | 1.47x | 1.70x |
| 25:1 | 2.97x | 2.20x | 3.11x | 2.75x |

**For round and mild aspect ratios the free-space kernel contributes essentially
none of the error.** It matters only as the beam flattens. This is the key fact
for the next section.

### 3.3 Vico-Greengard-Ferrando truncated kernel: derivation and rejection

The published critique of Hockney-Eastwood is that it is second-order accurate at
best, whereas the truncated-kernel method converges spectrally. Since only the
range $r\le L$ is needed, replace $G$ by $G_L = G\cdot\mathbb 1_{r\le L}$; the
transform of the truncated kernel is entire, so it can be evaluated analytically
on the mesh without sampling a singularity.

**2D transform.** With $G_{\text{phys}}=\ln r/(2\pi)$ and radial symmetry,

$$
    \widehat G_L(k)=\int_{r<L}\frac{\ln r}{2\pi}e^{-i\mathbf k\cdot\mathbf r}d^2r
    =\int_0^L r\ln r\,J_0(kr)\,dr .
$$

Integrating by parts with $u=\ln r$, $dv=rJ_0(kr)dr$, using
$\int rJ_0(kr)dr=(r/k)J_1(kr)$ and $\int_0^LJ_1(kr)dr=(1-J_0(kL))/k$,

$$
\boxed{\;
    \widehat G_L(k) = \frac{L\ln L}{k}J_1(kL) - \frac{1-J_0(kL)}{k^{2}},
    \qquad
    \widehat G_L(0)=\frac{L^{2}\,(2\ln L-1)}{4}.
\;}
$$

Verified against direct quadrature to $5\times10^{-13}$ (relative) across
$k\in[0,5.5\times10^4]$. The kernel used by the code's convention is
$-2\pi\widehat G_L$.

**Why it was rejected.** The truncation radius must exceed the largest
source-to-field separation in the box, i.e. the box *diagonal*, while the periodic
convolution only reproduces $G_L$ if $L$ fits inside half the padded period. With
the standard $2\times$ zero padding these are incompatible along the diagonal, and
the kernel aliases. Measured (round beam, grid 64):

| padding | $L$ | median | max |
| --- | --- | ---: | ---: |
| `:integrated` (current) | — | 2.88e-3 | 4.72e-3 |
| VGF $2\times$ | $1.45\,\text{box}$ (diagonal) | 4.1e-1 | 1.18e0 |
| VGF $2\times$ | $1.0\,\text{box}$ | 2.62e-3 | **1.08e-2** |
| VGF $3\times$ | $1.45\,\text{box}$ | **2.52e-3** | **4.20e-3** |

At equal cost ($2\times$ padding) the truncated kernel's tail error is $2.3\times$
*worse* than the integrated kernel. Making it work needs $3\times$ padding, i.e.
$2.25\times$ the FFT points in 2D — and the FFT is 32-37% of a CUDA turn — for a
12% accuracy gain. Combined with Section 3.2, which shows the kernel contributes
almost nothing to the error for round and mild aspect ratios, **VGF is not
recommended for this solver.** The item is closed on this measurement rather than
on the literature claim.

### 3.4 Lattice Green function: derivation and measurement

`docs/todo.md` carried "add a lattice Green-function variant" as an open PIC-core
item. Unlike the node-sampled and cell-integrated kernels, which discretize the
*continuum* $-\ln r$, the lattice Green function inverts the **five-point discrete
Laplacian exactly**, so the mesh solution satisfies the discrete Poisson equation
with no kernel truncation error at all.

**Construction.** Hockney's zero-padded convolution needs the *free-space* lattice
Green function, so the periodic $k$-space inverse $1/\kappa^2$ is not sufficient on
its own — it is the Green function of a torus and its zero mode diverges. Take the
infinite-lattice limit of the periodic one in the gauge $G(0,0)=0$:

$$
    G(\mathbf r) = -\frac{1}{M^2}\sum_{\mathbf k\neq0}
        \frac{\cos(\mathbf k\cdot\mathbf r)-1}{\kappa^2(\mathbf k)},
    \qquad
    \kappa^2 = \frac{2-2\cos\theta_x}{h_x^{2}} + \frac{2-2\cos\theta_y}{h_y^{2}},
$$

with $\theta=\mathbf k h$. The $(\cos-1)$ numerator removes the divergent zero mode and
fixes the gauge; the result converges to the infinite-lattice kernel for
$|m|,|n|\ll M$.

**Normalization.** To reproduce $\phi=\sum_j q_j(-\ln r_{ij})$, the kernel must satisfy
$L_h G = -2\pi\,\delta/(h_xh_y)$ — the Dirac delta discretizes to the Kronecker delta
over the *cell area*. With $L_h$ eigenvalues $-\kappa^2$,

$$
\boxed{\;\widehat G = \frac{2\pi}{\kappa^{2}h_xh_y},\qquad G = \frac{2\pi}{h_xh_y}\,
    \mathcal F^{-1}\!\left[\kappa^{-2}\right].\;}
$$

Verified against the continuum: at $h=10^{-4}$ the constructed kernel reproduces
$-\ln r$ to $1.8\times10^{-15}$ at $r=h$, with a residual $4.5\times10^{-2}$ offset at
larger $r$ that converges to a constant — the near-origin lattice correction, which
does not affect the field.

*A note on how this was nearly got wrong:* at $h_x=h_y=1$ the factor $2\pi/(h_xh_y)$
and a bare $2\pi$ coincide, so an isotropic unit-spacing sanity check cannot
distinguish them. The first version used the wrong power and produced a kernel
$10^{8}$ times too small — which showed up as a field error of exactly $0.95$,
*identical at every grid*, the signature of a computed field of zero.

**Measured** (identical deposit/grid/interpolation, median relative field error
against Bassetti-Erskine):

| case | grid | `:standard` | `:integrated` | `:lattice` | lattice vs integrated |
| --- | ---: | ---: | ---: | ---: | ---: |
| round | 64 | 7.79e-3 | **2.78e-3** | 3.03e-3 | 1.09x worse |
| round | 128 | 1.69e-3 | **6.05e-4** | 1.69e-3 | 2.80x worse |
| 11:1 (production) | 64 | 5.71e-2 | 6.53e-2 | **4.79e-2** | 1.36x better |
| 11:1 (production) | 128 | 1.88e-2 | 1.99e-2 | **1.35e-2** | 1.48x better |
| 25:1 | 64 | **8.55e-2** | 1.59e-1 | 1.35e-1 | 1.17x better |
| 25:1 | 128 | 1.07e-1 | 7.02e-2 | **5.13e-2** | 1.37x better |

**The result splits by aspect ratio.** The lattice kernel is *worse* for round
beams — up to 2.8x at 128 — and *better* for flat ones, including ~1.4x at the
11:1 production aspect ratio. This is consistent with Section 3.2: the kernel
contributes essentially none of the round-beam error, so replacing it there only
adds the lattice's own near-origin correction, while for flat beams the kernel is
a real error source.

**Recommendation: worth implementing, but not urgent, and not for dynamics.**
Two caveats decide the priority:

1. The gain is in *systematic* field error. The `:fourth` gradient bought a
   comparable ~1.6x and was measured to **not** reduce multi-turn emittance
   growth, which is shot-noise driven (Section 11 of the review). The same is
   expected here. It is a field-accuracy improvement, not a dynamics one.
2. Building it costs a large auxiliary FFT ($8\times$ the padded extent per axis).
   That is only affordable because of a property worth recording: factoring
   $h_x^{-2}$ out of $\kappa^2$ gives $G = 2\pi(h_x/h_y)\,\mathcal F^{-1}[f(\theta;h_x/h_y)]$,
   so **the kernel depends only on the grid size and the aspect ratio $h_x/h_y$**,
   not on the absolute spacing. It can therefore be built once per
   (grid, aspect ratio) and reused across slice pairs and turns, exactly like the
   slice-pair Green cache. Without that observation a per-pair rebuild would make
   it far too slow to use.

## References

1. R. W. Hockney and J. W. Eastwood, *Computer Simulation Using Particles*,
   McGraw-Hill (1981).
2. F. Vico, L. Greengard, M. Ferrando, "Fast convolution with free-space Green's
   functions", *J. Comput. Phys.* 323 (2016) 191.
3. J. Zou, E. Kim, A. J. Cerfon, "FFT-based free space Poisson solvers: why
   Vico-Greengard-Ferrando should replace Hockney-Eastwood" (2021),
   <https://arxiv.org/abs/2103.08531>.
4. M. Bassetti and G. A. Erskine, CERN-ISR-TH-80-06 (1980).
