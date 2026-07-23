# Spectral Sine-Series 2D Poisson Solver

This note derives a spectral solver for the transverse (2D) beam-beam Poisson
equation on a rectangular domain, using a double Fourier **sine** series. The
potential and charge density are expanded in the Dirichlet eigenfunctions of the
Laplacian, which diagonalizes the Poisson operator so that every mode is solved
by a single division. It also states the discrete (DST/FFT) form, the CUDA
parallelization, the open-boundary approximation this method makes, and the
generalization to circular and elliptical domains.

This is an alternative to the current `PICPoissonSolver`, which uses a
zero-padded FFT convolution with an integrated logarithmic Green function
(Hockney free-space method). The two solvers are compared in Section 11.

## 1. Problem and conventions

On the rectangular domain

$$
    \Omega = [0,a]\times[0,b],
$$

solve the 2D Poisson equation for the beam-beam potential $\phi$,

$$
    \nabla^2\phi(x,y) = k_{bb}\,\rho(x,y),
    \qquad
    \nabla^2 = \frac{\partial^2}{\partial x^2}+\frac{\partial^2}{\partial y^2},
$$

with homogeneous Dirichlet boundary conditions

$$
    \phi = 0 \quad\text{on}\quad \partial\Omega .
$$

Here $\rho$ is the transverse charge density (per unit transverse area) of the
source slice, and $k_{bb}$ is the coupling constant that absorbs the physical
normalization. In SI form the electrostatic Poisson equation is
$\nabla^2\phi = -\rho/\varepsilon_0$; the beam-beam coefficient additionally
carries the classical radius, charge product, source population, and relativistic
factor, so $k_{bb}$ here plays the same role as the `kbb` scale used by
`GaussianPoissonSolver`, `PICPoissonSolver`, and `ThinStrongBeam`. The transverse
kick applied to a field particle at $(x,y)$ is

$$
    \Delta\mathbf p_\perp = -\nabla\phi(x,y)
    = \left(-\frac{\partial\phi}{\partial x},\,-\frac{\partial\phi}{\partial y}\right).
$$

The signs propagate through $k_{bb}$; the derivation below is written for a
general $k_{bb}$.

## 2. Dirichlet eigenfunctions of the Laplacian

The eigenfunctions of $\nabla^2$ on $\Omega$ that vanish on $\partial\Omega$ are

$$
    \psi_{lm}(x,y) = \sin(\alpha_l x)\,\sin(\beta_m y),
    \qquad
    \alpha_l = \frac{l\pi}{a},\quad \beta_m = \frac{m\pi}{b},
    \qquad l,m = 1,2,3,\dots
$$

Because $\dfrac{d^2}{dx^2}\sin(\alpha_l x) = -\alpha_l^2\sin(\alpha_l x)$, each
mode is an eigenfunction of the Laplacian:

$$
    \nabla^2\psi_{lm} = -(\alpha_l^2+\beta_m^2)\,\psi_{lm}.
$$

Every $\psi_{lm}$ satisfies the boundary condition automatically:
$\sin(\alpha_l\cdot 0)=\sin(l\pi)=0$ and $\sin(\beta_m\cdot 0)=\sin(m\pi)=0$, so
$\psi_{lm}=0$ on all four edges $x=0,a$ and $y=0,b$.

**Boundary-condition note.** The sine basis enforces *homogeneous Dirichlet*
boundary conditions, $\phi|_{\partial\Omega}=0$. This is **not** the exact
free-space (open) boundary condition; it approximates it when the domain is
chosen much larger than the charge support, so that the true open-BC potential is
already negligible at $\partial\Omega$. The quality of this approximation is
discussed in Section 10.

## 3. Orthogonality

The 1D sine functions are orthogonal on $[0,a]$,

$$
    \int_0^a \sin(\alpha_l x)\,\sin(\alpha_{l'} x)\,dx = \frac{a}{2}\,\delta_{ll'},
$$

and likewise on $[0,b]$. Hence the 2D modes are orthogonal,

$$
    \int_\Omega \psi_{lm}\,\psi_{l'm'}\,dA
    = \frac{a}{2}\,\frac{b}{2}\,\delta_{ll'}\delta_{mm'}
    = \frac{ab}{4}\,\delta_{ll'}\delta_{mm'}.
$$

## 4. Sine-series expansion and coefficients

Expand both fields in the eigenbasis:

$$
    \rho(x,y) = \sum_{l,m\ge 1}\rho_{lm}\,\psi_{lm}(x,y),
    \qquad
    \phi(x,y) = \sum_{l,m\ge 1}\phi_{lm}\,\psi_{lm}(x,y).
$$

By orthogonality (Section 3), the coefficients are

$$
\boxed{\;
    \rho_{lm} = \frac{4}{ab}\int_0^a\!\!\int_0^b
        \rho(x,y)\,\sin(\alpha_l x)\,\sin(\beta_m y)\,dx\,dy,
\;}
$$

and identically for $\phi_{lm}$ with $\phi$ in place of $\rho$.

## 5. Mode-by-mode solution

Substitute the expansions into the Poisson equation and use the eigenvalue
relation of Section 2:

$$
    \nabla^2\phi = \sum_{l,m}\phi_{lm}\nabla^2\psi_{lm}
    = -\sum_{l,m}(\alpha_l^2+\beta_m^2)\,\phi_{lm}\,\psi_{lm}
    \stackrel{!}{=} k_{bb}\sum_{l,m}\rho_{lm}\,\psi_{lm}.
$$

Matching coefficients of each orthogonal mode gives

$$
    -(\alpha_l^2+\beta_m^2)\,\phi_{lm} = k_{bb}\,\rho_{lm},
$$

so the potential coefficients follow by a single division per mode:

$$
\boxed{\;
    \phi_{lm} = -\,\frac{k_{bb}\,\rho_{lm}}{\alpha_l^2+\beta_m^2}
             = -\,\frac{k_{bb}\,\rho_{lm}}{(l\pi/a)^2+(m\pi/b)^2}.
\;}
$$

Because $l,m\ge 1$, the denominator satisfies
$\alpha_l^2+\beta_m^2 \ge (\pi/a)^2+(\pi/b)^2 > 0$ for **every** mode. There is no
singular zero mode. (Contrast the periodic-FFT Poisson solver, whose $k=0$ mode
is singular and requires a neutralizing background.)

## 6. Charge-density coefficients from macroparticles

For a slice of $N_p$ macroparticles at transverse positions $(x_p,y_p)$ carrying
charge (or weight) $q_p$, the density is a sum of delta functions,

$$
    \rho(x,y) = \sum_{p=1}^{N_p} q_p\,\delta(x-x_p)\,\delta(y-y_p).
$$

The coefficient integral of Section 4 collapses to a direct sum:

$$
\boxed{\;
    \rho_{lm} = \frac{4}{ab}\sum_{p=1}^{N_p}
        q_p\,\sin(\alpha_l x_p)\,\sin(\beta_m y_p).
\;}
$$

This is a **grid-free spectral deposition**: the modes are formed directly from
particle positions, with cost $O(N_p\,L\,M)$ for $L\times M$ retained modes.

Alternatively, deposit the macroparticles onto a uniform mesh with a shape
function (CIC/TSC), then obtain $\rho_{lm}$ from the discrete sine transform of
the gridded charge (Section 9). The grid deposition costs $O(N_p)$ plus a fast
$O(N^2\log N)$ transform and provides implicit smoothing through the shape
function; it is the preferred route for large $N_p$.

## 7. Field and kick evaluation

Differentiate the potential series term by term:

$$
\begin{aligned}
    \frac{\partial\phi}{\partial x}
      &= \sum_{l,m}\phi_{lm}\,\alpha_l\,\cos(\alpha_l x)\,\sin(\beta_m y),\\
    \frac{\partial\phi}{\partial y}
      &= \sum_{l,m}\phi_{lm}\,\beta_m\,\sin(\alpha_l x)\,\cos(\beta_m y).
\end{aligned}
$$

The transverse kick $\Delta\mathbf p_\perp = -\nabla\phi$ is therefore, after
inserting $\phi_{lm}$ from Section 5,

$$
\boxed{
\begin{aligned}
    \Delta p_x(x,y) &= k_{bb}\sum_{l,m}
        \frac{\alpha_l\,\rho_{lm}}{\alpha_l^2+\beta_m^2}\,
        \cos(\alpha_l x)\,\sin(\beta_m y),\\
    \Delta p_y(x,y) &= k_{bb}\sum_{l,m}
        \frac{\beta_m\,\rho_{lm}}{\alpha_l^2+\beta_m^2}\,
        \sin(\alpha_l x)\,\cos(\beta_m y).
\end{aligned}
}
$$

Each field particle is kicked by evaluating these truncated sums at its own
$(x,y)$, or by interpolating a precomputed field grid built from the same mode
coefficients (Section 9).

## 8. Spectral truncation

The series are truncated at maximum modes $L$ and $M$:

$$
    l = 1,\dots,L,\qquad m = 1,\dots,M.
$$

$L$ and $M$ are the user-controllable accuracy knobs. For a smooth density the
sine coefficients decay rapidly, giving spectral (super-algebraic) convergence,
so modest $L,M$ suffice. A source that is sharply localized or strongly
anisotropic requires larger $L,M$; see the flat-beam caveat in Section 13.

## 9. Discrete implementation via the sine transform

On a uniform interior mesh $x_i = i\,h_x$, $h_x = a/(N_x+1)$, $i=1,\dots,N_x$
(and analogously in $y$), the coefficient integrals become the type-I discrete
sine transform (DST-I):

$$
    \tilde\rho_{lm} = \sum_{i=1}^{N_x}\sum_{j=1}^{N_y}
        \rho_{ij}\,\sin\!\Big(\frac{l\pi i}{N_x+1}\Big)
                  \sin\!\Big(\frac{m\pi j}{N_y+1}\Big).
$$

The full solve is:

1. **Deposit** particles onto the interior mesh (CIC/TSC), or form
   $\tilde\rho_{lm}$ directly from particles (Section 6).
2. **Forward DST-I** in both dimensions: $\rho_{ij}\to\tilde\rho_{lm}$.
3. **Divide** each mode: $\tilde\phi_{lm} = -k_{bb}\,\tilde\rho_{lm}/(\alpha_l^2+\beta_m^2)$.
4. **Inverse DST-I** (DST-I is its own inverse up to the factor $2(N_x+1)$ per
   dimension): $\tilde\phi_{lm}\to\phi_{ij}$.
5. **Differentiate** for the field, either spectrally (multiply by $\alpha_l$ /
   $\beta_m$ before the inverse transform, using cosine transforms for the
   derivative) or by finite differences on $\phi_{ij}$, then interpolate to
   particles.

Because both $\rho$ and $\phi$ use the same transform convention, the overall
DST normalization cancels in step 3; only the final inverse transform carries the
$1/[2(N_x+1)\,2(N_y+1)]$ factor. The DST-I is computed by FFT, so the solve is
$O(N_x N_y \log(N_x N_y))$. Unlike the Hockney method, the mesh is **not** doubled
(no zero padding), which halves the transform size in each dimension.

## 10. Open-boundary approximation and domain sizing

The exact free-space (open) 2D potential of a net charge $Q$ behaves like
$-\tfrac{Q}{2\pi}\ln r$ at large $r$; it does not decay to zero. The Dirichlet box
forces $\phi=0$ at $\partial\Omega$, so it truncates this logarithmic tail. The
difference between the boxed and free-space potentials is a harmonic function
inside $\Omega$ (it satisfies Laplace's equation, since both solve the same
Poisson equation), and near the beam it is smooth and slowly varying. The
**field** error near the source therefore decreases as the domain grows,
roughly like $O(1/a)$ for the correction's gradient. In practice the domain is
chosen several to ten times the beam size; the required size is larger than for
the exact Hockney method because of the 2D logarithm. The domain size $a,b$ is a
convergence parameter that must be validated per beam aspect ratio.

## 11. Comparison to the integrated-Green-function (Hockney) solver

| | Sine-series (this note) | Zero-padded Green FFT (current `PICPoissonSolver`) |
| --- | --- | --- |
| Boundary condition | homogeneous Dirichlet (approx. open, large box) | exact open / free-space |
| Domain | single mesh $N_x\times N_y$ | doubled mesh $2N_x\times 2N_y$ |
| Green function | none (direct mode division) | integrated log kernel, cached FFT |
| Zero mode | none ($\alpha_l^2+\beta_m^2>0$) | handled by the Green kernel |
| Transform | DST-I (FFT) | complex FFT convolution |
| Memory | lower (no padding) | higher (4x padded planes) |
| Open-BC accuracy | depends on domain size | exact to grid resolution |
| Accuracy knob | max modes $L,M$ and domain $a,b$ | grid size and Green kernel |

The sine method trades the exact open boundary of Hockney for a simpler, lower
memory, zero-mode-free solve whose open-BC accuracy is controlled by the domain
size.

## 12. Circular and elliptical domains

The same idea applies on other separable domains by expanding in that domain's
Dirichlet Laplacian eigenfunctions.

**Disk of radius $R$** (Dirichlet $\phi(R,\theta)=0$). Use the Fourier-Bessel
basis

$$
    \psi_{nk}(r,\theta) = J_n\!\Big(\frac{j_{nk}}{R}\,r\Big)\,e^{in\theta},
$$

where $J_n$ is the Bessel function of order $n$ and $j_{nk}$ is its $k$-th
positive zero, so that $\psi_{nk}(R,\theta)=0$. These satisfy
$\nabla^2\psi_{nk} = -(j_{nk}/R)^2\,\psi_{nk}$, giving the mode solution

$$
    \phi_{nk} = -\,\frac{k_{bb}\,\rho_{nk}}{(j_{nk}/R)^2}.
$$

The azimuthal direction is a standard FFT ($\theta\to n$); the radial coefficients
$\rho_{nk}$ require a Bessel (Hankel-type) transform, which is not a plain FFT and
is less GPU-standard.

**Elliptical domain.** The separable Dirichlet eigenfunctions are products of
Mathieu functions; the mode solve has the same form but the transforms are
specialized and expensive.

For CUDA, the rectangular sine method is preferred because every stage is a
standard FFT/DST.

## 13. CUDA parallelization

Every stage maps to a strong GPU primitive, and the solve is embarrassingly
parallel over modes:

- **Deposition** onto the mesh: atomic scatter (as in the current PIC path); or
  the grid-free particle-to-mode sum, which is a dense reduction.
- **Forward/inverse DST-I**: batched cuFFT (DST-I is realized through the FFT of
  a symmetric extension). The 225 slice-pair solves per turn batch naturally, as
  they already do for the Hockney path.
- **Mode division** $\tilde\phi_{lm} = -k_{bb}\tilde\rho_{lm}/(\alpha_l^2+\beta_m^2)$:
  an element-wise kernel, trivially parallel, with the reciprocal denominators
  precomputable once per (domain, grid).
- **Field evaluation**: spectral derivative (cosine transform) or finite
  differences, then gather to particles.

There is no zero-mode special case and no doubled grid, so the memory footprint
and kernel count are lower than the Hockney path.

**Flat-beam caveat.** Beam-beam distributions are often strongly elliptical
($\sigma_x/\sigma_y \sim 10$--$30$). A flat source has sharp variation along its
thin direction, so it needs many modes there ($M$ large if $y$ is the thin
axis) for the series to converge. Choose $L,M$ and the mesh anisotropically to
match the beam aspect ratio, and validate the mode count against the
Bassetti-Erskine field before production use.

## 14. Correctness

**Analytic.**

1. Boundary: $\psi_{lm}=0$ on all edges (Section 2), so any truncated series
   satisfies $\phi|_{\partial\Omega}=0$ exactly.
2. Eigenvalue: $\nabla^2\psi_{lm}=-(\alpha_l^2+\beta_m^2)\psi_{lm}$ (Section 2).
3. Orthogonality gives the coefficient formula (Sections 3-4).
4. Mode matching gives $\phi_{lm}=-k_{bb}\rho_{lm}/(\alpha_l^2+\beta_m^2)$
   (Section 5); no zero mode since $l,m\ge 1$.
5. Single-mode self-consistency: for $\rho=\rho_0\psi_{lm}$,
   $\phi=-k_{bb}\rho_0\psi_{lm}/(\alpha_l^2+\beta_m^2)$ and
   $\nabla^2\phi = k_{bb}\rho_0\psi_{lm} = k_{bb}\rho$.

**Numerical** (verified on an arbitrary domain $a=1.3$, $b=0.8$, coupling
$k_{bb}=-2.5$, $N=63$ interior points per dimension, FFTW DST-I):

- **Manufactured band-limited solution.** With
  $\phi_{\text{ex}} = \sin(\pi x/a)\sin(\pi y/b) + \tfrac12\sin(2\pi x/a)\sin(3\pi y/b)
   - 0.3\sin(4\pi x/a)\sin(\pi y/b)$ and $\rho = \nabla^2\phi_{\text{ex}}/k_{bb}$,
  the solver recovers $\phi_{\text{ex}}$ to a maximum relative error of
  $9.6\times10^{-16}$ (machine precision), confirming the mode-division formula.
- **Gaussian source** ($\sigma=0.07$, centered): the five-point finite-difference
  Laplacian of the spectral $\phi$ matches $k_{bb}\rho$ in the interior to
  $7.2\times10^{-3}$ (spectral-versus-finite-difference discretization plus
  truncation, shrinking with resolution/modes), and $\phi$ at the row nearest the
  boundary is $1.3\%$ of the interior maximum, consistent with a well-contained
  source in a Dirichlet box.

## 15. Integration and validation plan

Add the solver as an `AbstractPoissonSolver` variant (or a `green_type`/method
option), reusing the existing deposition, slicing, and kick infrastructure and
the physical `kbb1/kbb2` and `luminosity_scale` conventions. Required checks
before it becomes selectable:

- `validation/pic_gaussian_field_validation.jl`: compare the spectral field to
  the Bassetti-Erskine field across round and high-aspect-ratio beams, sweeping
  the mode counts $L,M$ and the domain size $a,b$ to establish convergence.
- `StrongStrongPICBackendConsistencyContract`-style CPU/CUDA agreement for the
  new path.
- A domain-size and truncation study documented alongside the extreme-benchmark
  history.

## 16. Parameter selection and measured accuracy

Measured with `validation/spectral_poisson_field_validation.jl` against the exact
Bassetti-Erskine field (`gaussian_beambeam_kick`), on a $\pm 4\sigma$ field grid,
with the field-shape residual normalized by the maximum exact kick and calibrated
by a least-squares constant (so the comparison isolates spatial accuracy, not the
overall coupling). All relative errors below are medians.

**Domain size dominates for round beams.** The rectangular half-widths must be
sized to the **larger** beam dimension in **both** directions,
$L_x = L_y \approx d\cdot\max(\sigma_x,\sigma_y)$, because the 2D free-space
potential decays only logarithmically. The error falls roughly like $1/d^2$:

| domain factor $d$ | 4 | 6 | 10 | 16 | 24 |
| --- | ---: | ---: | ---: | ---: | ---: |
| median rel. error | 8.8e-2 | 2.2e-2 | 4.0e-3 | 1.3e-3 | 1.0e-3 |

Use $d\approx 12$--$16$ for sub-$0.2\%$ round-beam accuracy.

**Thin-direction resolution dominates for flat beams.** Since the domain in the
thin direction is $d\cdot\sigma_\text{large}$, resolving $\sigma_\text{small}$
requires an **anisotropic** mesh with

$$
    N_\text{thin} \approx 4\text{--}6\; d\; \frac{\sigma_\text{large}}{\sigma_\text{small}},
    \qquad
    N_\text{thick} \approx 2\text{--}4\,d .
$$

The error falls like $1/N_\text{thin}$ (flat 25:1, $d=8$):

| $N_\text{thin}$ | 128 | 256 | 512 | 1024 |
| --- | ---: | ---: | ---: | ---: |
| median rel. error | 8.1e-2 | 3.4e-2 | 1.3e-2 | 7.8e-3 |

So a $25{:}1$ beam needs $N_\text{thin}\sim 1000$ for sub-$1\%$. **The thin-axis
mode count grows linearly with the aspect ratio** — the central practical cost of
this method for flat colliding beams. A uniform (isotropic) mesh is wasteful;
always split $N_x$ and $N_y$.

**Grid versus grid-free complexity.**

| variant | deposition | solve | field eval | practical use |
| --- | --- | --- | --- | --- |
| grid-free | $O(N_p L M)$ | $O(LM)$ | $O(N_f L M)$ | round beams, few modes, reference |
| grid (DST) | $O(N_p)$ | $O(N_x N_y\log)$ | $O(N_x N_y)+O(N_f)$ | production; required for flat beams |

The grid (DST) variant is $10^2$--$10^3\times$ faster than grid-free at matched
accuracy and is the only practical choice when many modes are needed. Grid-free
is retained as a deposition-error-free reference.

**Accuracy relative to PIC.** On identical sources and field grids, the spectral
solver is **comparable to, not dramatically better than**, the current Hockney
PIC solver: median field-shape errors of $\sim 0.1$--$0.2\%$ (round),
$\sim 0.2$--$0.8\%$ (5:1), and $\sim 1$--$2\%$ (25:1), against PIC's $0.16\%$,
$0.22\%$, and $0.94\%$. The spectral method tends to have a lower maximum error
and no singular zero mode or doubled grid, while PIC is often more accurate per
unit cost at moderate resolution. The spectral grid variant above uses a
second-order finite-difference field gradient; replacing it with an exact
spectral (cosine-transform) derivative is the clearest path to improve its field
accuracy beyond PIC.

**Recommended defaults.**

- Round or mild aspect ratio: $d = 12$--$16$, $N_x = N_y \approx 4d$ ($\sim 128$).
- Aspect ratio $r$: $L_x=L_y = 8\,\sigma_\text{large}$, $N_x \approx 32$,
  $N_y \approx 5\,d\,r$ (anisotropic), grid (DST) variant.
- Validate the chosen $d$, $N_x$, $N_y$ against Bassetti-Erskine for the actual
  beam aspect ratio before production use.

## References

1. R. W. Hockney and J. W. Eastwood, *Computer Simulation Using Particles*,
   McGraw-Hill (1981). FFT Poisson solvers and open-boundary (isolated system)
   convolution.
2. M. Bassetti and G. A. Erskine, "Closed expression for the electrical field of
   a two-dimensional Gaussian charge," CERN-ISR-TH-80-06 (1980).
3. J. Qiang, M. A. Furman, and R. D. Ryne, "A parallel particle-in-cell model for
   beam-beam interaction in high energy ring colliders," *J. Comput. Phys.* 198
   (2004), 278-294.
