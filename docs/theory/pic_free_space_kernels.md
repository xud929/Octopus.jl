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

## References

1. R. W. Hockney and J. W. Eastwood, *Computer Simulation Using Particles*,
   McGraw-Hill (1981).
2. F. Vico, L. Greengard, M. Ferrando, "Fast convolution with free-space Green's
   functions", *J. Comput. Phys.* 323 (2016) 191.
3. J. Zou, E. Kim, A. J. Cerfon, "FFT-based free space Poisson solvers: why
   Vico-Greengard-Ferrando should replace Hockney-Eastwood" (2021),
   <https://arxiv.org/abs/2103.08531>.
4. M. Bassetti and G. A. Erskine, CERN-ISR-TH-80-06 (1980).
