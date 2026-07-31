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

The adaptive mesh width is normally derived from particle extrema or RMS. If an
axis is exactly degenerate, that data-derived width is zero and a two-dimensional
cell area cannot be formed. `min_transverse_extent` supplies an explicit
physical width in particle-coordinate units for such an axis; its default
`(0,0)` adds no artificial scale. Machine epsilon is not a valid replacement
because it is dimensionless and changes with floating-point precision.

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

Three kernels are available through `green_type`: `:integrated` (default,
production), `:standard` (round beams only), and `:lattice` (**experimental**,
flat-beam field-accuracy studies only — see Section 3.5 for its cost).

### 3.1 Node-sampled (`green_type=:standard`)

$G$ evaluated at node separations, $G_{ij}=-\tfrac12\ln r_{ij}^2$, with the
singular self-term replaced by the analytic average over its finite source cell.
This avoids introducing a machine-epsilon value with the dimensions of
$r^2$. The normal interaction-grid alignment offsets source and field nodes by
half a cell, so the replacement is only exercised by an exactly coincident
source/field grid. This kernel is cheapest to build and adequate for round beams,
but it samples a function with a logarithmic singularity away from that one cell,
so its accuracy degrades as cells become anisotropic.

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

**Eigenvalues of the stencil.** Applying the five-point operator to a lattice plane
wave $\psi_{mn}=e^{i(\theta_xm+\theta_yn)}$,

$$
    L_h\psi = \left[\frac{e^{i\theta_x}-2+e^{-i\theta_x}}{h_x^{2}}
                  + \frac{e^{i\theta_y}-2+e^{-i\theta_y}}{h_y^{2}}\right]\psi
            = -\left[\frac{2-2\cos\theta_x}{h_x^{2}}+\frac{2-2\cos\theta_y}{h_y^{2}}\right]\psi
            \equiv -\kappa^2\psi ,
$$

so $L_h$ is diagonal in the DFT basis with eigenvalue $-\kappa^2$. (Expanding
$2-2\cos\theta=\theta^2-\theta^4/12+\dots$ recovers $\kappa^2\to k^2$ as $h\to0$, which is
the usual second-order consistency of the stencil.)

**Normalization.** To reproduce $\phi=\sum_j q_j(-\ln r_{ij})$, the kernel must satisfy
$L_h G = -2\pi\,\delta/(h_xh_y)$ — the Dirac delta discretizes to the Kronecker delta
over the *cell area*. With $L_h$ eigenvalues $-\kappa^2$,

$$
\boxed{\;\widehat G = \frac{2\pi}{\kappa^{2}h_xh_y},\qquad G = \frac{2\pi}{h_xh_y}\,
    \mathcal F^{-1}\!\left[\kappa^{-2}\right].\;}
$$

**Asymptotics, and why the kernel is usable at all.** The construction is only
legitimate if $G$ reproduces $-\ln r$ far from the origin. It does, and the constant
is known in closed form. For the isotropic square lattice, Spitzer's potential
kernel $a(\mathbf r)$ (gauge $a(0)=0$, $L a=\delta$) satisfies

$$
\boxed{\;a(\mathbf r) = \frac{1}{2\pi}\Big(\ln r + \gamma + \tfrac32\ln 2\Big) + O(r^{-2}),\;}
$$

with $\gamma$ the Euler-Mascheroni constant. Since $\widehat G\propto+\kappa^{-2}$ inverts
$L_hg=-\delta$, the raw transform gives $g=-a$, so the scaled kernel obeys
$G_{\text{PIC}}=2\pi g\to-(\ln r + C)$ with $C=\gamma+\tfrac32\ln2=1.6169364$. The additive
$C$ is a gauge constant and does not affect the field.

Three numerical confirmations, all against values fixed *before* the run:

| quantity | computed | exact | agreement |
| --- | ---: | ---: | ---: |
| nearest neighbour $a(1,0)$ | 0.2499997616 | $1/4$ | 2.4e-7 |
| asymptotic constant $C$ | 1.6162246 | $\gamma+\tfrac32\ln2$ | 7.1e-4 |
| residual when anchored at $r=h$ | 4.47-4.54e-2 | $C-\pi/2$ = 0.046140 | matches |

The nearest-neighbour value $a(1,0)=1/4$ is the exact lattice result behind the
classic "infinite grid of $1\,\Omega$ resistors has $\tfrac12\,\Omega$ between adjacent
nodes", since $R=2[a(1,0)-a(0,0)]$.

The third row **derives** a number that was previously only observed. Verifying the
kernel by anchoring it at $r=h$ forces exact agreement there, so the leftover offset
at large $r$ must be exactly $C-2\pi a(1,0)=\gamma+\tfrac32\ln2-\pi/2=0.046140$. The
measured $4.47$-$4.54\times10^{-2}$ is that quantity, not an error: it is the
near-origin lattice correction, and being a constant it does not affect the field.

**Validity window.** The infinite-lattice limit requires $|m|,|n|\ll M$. Measured
convergence to $C$ at $M=1024$ is 6.2e-3 at $r=4$, best at 7.1e-4 at $r=16$, then
*degrading* to 3.5e-3 by $r=48$ as periodic wraparound re-enters. That non-monotonic
behaviour is the signature of the two competing errors — the $O(r^{-2})$ asymptotic
tail and the finite-box contamination — and it is what sets the box multiplier: the
padded extent must be a comfortable fraction of $M$, hence the $8\times$ used here.

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

### 3.5 Implemented as `green_type=:lattice` (EXPERIMENTAL) — and what implementing it revealed

> **Status: EXPERIMENTAL.** `:lattice` is supported for **flat-beam
> field-accuracy studies only**. It is correct and covered by CPU/CUDA parity
> tests, but it is **not a recommended production configuration**: 1.74x runtime
> and ~645 MB at grid 128, for a gain in *systematic* field error that is not
> expected to change shot-noise-driven multi-turn results. Its caching behaviour
> may change. `:integrated` remains the default and the production choice.

Implemented on CPU and all CUDA routes (2026-07-25). CPU/CUDA parity is **1e-17**,
better than `:integrated`'s 1.3e-16, because the table is built once on the host
and uploaded, so the kernel values are bit-identical across backends by
construction.

**The caching argument in Section 3.4 was wrong in practice, and measuring it is
what showed that.** The claim was that because $G$ depends only on the grid and
the aspect ratio $\rho=h_x/h_y$, one table per $(\text{grid},\rho)$ would serve every
slice pair and turn. Two measurements refute the *affordability* half of it:

1. **Production has hundreds of distinct aspect ratios, not a handful.** A
   single-turn probe suggested ~18 at 1% quantization. An actual 18-turn,
   15-slice run needs **306** distinct tables — 2.1 MB each at grid 128, so ~645 MB.
2. **The quantization cannot be coarsened to fix that,** because accuracy is
   sharply sensitive to $\rho$. At the 11:1 production beams, grid 128
   (`:integrated` reference 1.991e-2):

   | $\rho$ error | median field error | versus `:integrated` |
   | ---: | ---: | --- |
   | exact | 1.348e-2 | 1.48x better |
   | 0.5% (as shipped) | 1.529e-2 | 1.30x better |
   | **2%** | 2.055e-2 | **worse** |
   | 5% | 3.055e-2 | 1.5x worse |

   Beyond ~2% aspect error the lattice kernel is worse than the kernel it was
   meant to replace. So the table must track $\rho$ closely, and the cache cannot
   be made small.

**Measured cost** (CUDA, 1.024M per beam, 15 slices, per turn):

| grid | `:integrated` | `:lattice` | ratio |
| ---: | ---: | ---: | ---: |
| 64 | 0.191 | 0.249 | 1.30x |
| 128 | 0.253 | 0.440 | 1.74x |

The cache is capped at 384 entries to bound memory. The cap must be generous: at
64 entries it thrashes and the cost rises from 1.8x to **6.8x** a turn.

**Recommendation: opt-in for flat-beam field-accuracy work; do not use in
production.** The honest trade at the production aspect ratio is 1.30x lower
systematic field error for 1.74x runtime and ~645 MB. Since the gain is in
systematic error, and the analogous `:fourth` gradient bought a comparable factor
while measurably *not* reducing shot-noise-driven emittance growth, this is very
unlikely to change a multi-turn dynamics result.

**The concrete route to making it cheap**, if it is ever wanted in production: the
lattice correction decays as $O(r^{-2})$, so a small lattice patch near the origin
plus the analytic asymptotic $-(\ln r + C)$ beyond would cut the auxiliary FFT from
$M=2048$ to $M\sim256$ and shrink the table by orders of magnitude. Measured decay
for the isotropic case supports this directly (correction 4.6e-2 at $r=1$, 7.2e-4
by $r=8$). The anisotropic case is the open part: at $\rho=11$ the correction is
still ~5.9e-2 at $r=16$ in coarse-axis cells, so the patch radius and the
anisotropic constant $C(\rho)$ both need deriving before this is safe.

**Original recommendation (superseded by the measurements above):**
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
