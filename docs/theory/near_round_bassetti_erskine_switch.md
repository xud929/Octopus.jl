# Near-Round Bassetti-Erskine Evaluation and Switch Estimate

This note derives an accuracy-based transition between the elliptical
Bassetti-Erskine field and its round-beam limit. It applies to the analytic
Gaussian field used by weak-strong tracking, the soft-Gaussian strong-strong
solver, and the analytic add-back in the Gaussian-subtracted PIC solver.

The note distinguishes three questions that a single hard-coded number cannot
answer by itself:

1. How much physical ellipticity is discarded by using the round formula?
2. How ill-conditioned is the elliptical formula near equal beam sizes?
3. What continuity is required of the transverse force, Hessian, and
   longitudinal kick?

This is a derivation and switch-design note. It does not claim that the
recommended near-round expansion is implemented. The current implementation
still uses `ROUND_BEAM_THRESHOLD = 1e-10`.

Related notes:

- [Synchro-Beam Longitudinal Kick](beam_beam_longitudinal_kick.md) derives the
  covariance-dependent longitudinal kick and explains why the Hessian must be
  consistent with the transverse field.
- [Gaussian-Subtracted PIC Poisson Solver](gaussian_subtracted_pic_solver.md)
  states the Bassetti-Erskine convention used throughout the code.

## 1. Covariance and anisotropy conventions

Work in the principal axes of the transverse source covariance. Let its
eigenvalues be

$$
    \lambda_1=\sigma_1^2,
    \qquad
    \lambda_2=\sigma_2^2,
    \qquad
    \lambda_1\geq\lambda_2>0.
$$

Define the mean variance and invariant variance anisotropy

$$
    s^2=\frac{\lambda_1+\lambda_2}{2},
    \qquad
    \eta
      =\frac{\lambda_1-\lambda_2}{\lambda_1+\lambda_2}.
$$

Thus

$$
    \lambda_1=s^2(1+\eta),
    \qquad
    \lambda_2=s^2(1-\eta),
    \qquad
    0\leq\eta<1.
$$

The size-based quantity currently used by the uncoupled implementation is

$$
    \delta_\sigma
      =\frac{\sigma_1-\sigma_2}{\sigma_1+\sigma_2}.
$$

The two measures are related exactly:

$$
    \eta=\frac{2\delta_\sigma}{1+\delta_\sigma^2},
    \qquad
    \delta_\sigma
      =\frac{\eta}{1+\sqrt{1-\eta^2}}.
$$

Near a round beam,

$$
    \eta=2\delta_\sigma+O(\delta_\sigma^3).
$$

The covariance definition $\eta$ is preferable because it is invariant under a
rotation of the transverse coordinates and applies unchanged to a coupled
covariance. For

$$
    A=
    \begin{pmatrix}a&b\\b&d\end{pmatrix},
$$

it is

$$
    \eta
      =
      \frac{\sqrt{(a-d)^2+4b^2}}{a+d}.
$$

The current code uses $\delta_\sigma$ in the uncoupled field evaluator but
$\eta$ in the coupled-covariance branch. Comparing both to the same numerical
constant therefore gives thresholds that differ by approximately a factor of
two near roundness.

## 2. Exact integral on a fixed interval

Let $(x,y)$ denote coordinates in the covariance principal frame and define

$$
    X=\frac{x}{s},
    \qquad
    Y=\frac{y}{s},
    \qquad
    q=\frac{X^2+Y^2}{2},
    \qquad
    d_r=\frac{X^2-Y^2}{2}.
$$

The subscript on $d_r$ distinguishes this radial-angular variable from a
covariance entry.

Starting from the Gaussian-potential integral in
[Synchro-Beam Longitudinal Kick](beam_beam_longitudinal_kick.md), substitute

$$
    z=\frac{s^2}{s^2+t}.
$$

The semi-infinite interval $t\in[0,\infty)$ becomes $z\in[0,1]$. The two force
components are

$$
\begin{aligned}
    K_x
      ={}&\frac{x}{s^2}
      \int_0^1
      \frac{
        \exp\!\left[
          -\frac z2
          \left(
            \frac{X^2}{1+\eta z}
            +
            \frac{Y^2}{1-\eta z}
          \right)
        \right]
      }{
        (1+\eta z)^{3/2}(1-\eta z)^{1/2}
      }
      \,dz,\\
    K_y
      ={}&\frac{y}{s^2}
      \int_0^1
      \frac{
        \exp\!\left[
          -\frac z2
          \left(
            \frac{X^2}{1+\eta z}
            +
            \frac{Y^2}{1-\eta z}
          \right)
        \right]
      }{
        (1+\eta z)^{1/2}(1-\eta z)^{3/2}
      }
      \,dz.
\end{aligned}
$$

This representation is smooth at $\eta=0$ and is suitable for a high-precision
reference calculation. At $\eta=0$,

$$
    K_x=\frac{x}{s^2}M_0(q),
    \qquad
    K_y=\frac{y}{s^2}M_0(q),
$$

where

$$
    M_n(q)
      =\int_0^1 z^n e^{-qz}\,dz,
    \qquad
    M_0(q)=\frac{1-e^{-q}}{q}.
$$

This is the round field

$$
    \mathbf K_{\mathrm{round}}
      =
      \frac{2(1-e^{-r^2/(2s^2)})}{r^2}
      \begin{pmatrix}x\\y\end{pmatrix}.
$$

For numerical reference work, the moments can be evaluated from their
small-$q$ series

$$
    M_n(q)
      =
      \sum_{k=0}^{\infty}
      \frac{(-q)^k}{k!(n+k+1)}
$$

or, away from zero, by

$$
    M_n(q)
      =
      \frac{nM_{n-1}(q)-e^{-q}}{q}.
$$

The recurrence should not be used at small $q$ because its numerator then
subtracts nearly equal quantities.

## 3. Near-round expansion

Introduce

$$
    s_x=-1,
    \qquad
    s_y=+1.
$$

Expanding the logarithm of each force integrand through third order gives

$$
    I_j(z;\eta)
      =
      e^{-qz}
      \left[
        1+\eta A_{1,j}(z)
        +\eta^2 A_{2,j}(z)
        +\eta^3 A_{3,j}(z)
        +O(\eta^4)
      \right].
$$

After collecting powers of $z$, write

$$
    K_j
      =
      \frac{r_j}{s^2}
      \left[
        C_0+\eta C_{1,j}+\eta^2 C_{2,j}
        +\eta^3 C_{3,j}+O(\eta^4)
      \right],
$$

where $r_x=x$, $r_y=y$, and

$$
    C_0=M_0,
$$

$$
    C_{1,j}
      =
      d_rM_2+s_jM_1,
$$

$$
    C_{2,j}
      =
      \frac32M_2
      +(s_jd_r-q)M_3
      +\frac{d_r^2}{2}M_4,
$$

and

$$
\begin{aligned}
    C_{3,j}
      ={}&
      \frac{3s_j}{2}M_3
      +\left(\frac{5d_r}{2}-s_jq\right)M_4\\
      &+\left(-d_rq+\frac{s_jd_r^2}{2}\right)M_5
      +\frac{d_r^3}{6}M_6.
\end{aligned}
$$

These coefficients follow directly from the fixed-interval integral; no
Faddeeva subtraction appears. They can be evaluated with real arithmetic and
are regular on the axis.

At $q=0$, where $M_n(0)=1/(n+1)$ and $d_r=0$,

$$
\begin{aligned}
    C_{1,x}&=-\frac12,
    &C_{1,y}&=+\frac12,\\
    C_{2,x}&=\frac12,
    &C_{2,y}&=\frac12,\\
    C_{3,x}&=-\frac38,
    &C_{3,y}&=+\frac38.
\end{aligned}
$$

The same result follows from the exact linear field at the origin:

$$
    \lim_{x\to0}\frac{K_x}{x}
      =
      \frac{2}{\sigma_1(\sigma_1+\sigma_2)},
    \qquad
    \lim_{y\to0}\frac{K_y}{y}
      =
      \frac{2}{\sigma_2(\sigma_1+\sigma_2)}.
$$

The origin is consequently an important validation point. A scan of the
analytic coefficients over $0\leq q\leq100$ and
$0\leq\theta\leq\pi/2$, with
$X=\sqrt{2q}\cos\theta$ and $Y=\sqrt{2q}\sin\theta$, gives maximum
relative force-vector coefficients. Specifically, define

$$
    R_n(q,\theta)
      =
      \frac{
        \sqrt{
          X^2C_{n,x}^2+Y^2C_{n,y}^2
        }
      }{
        \sqrt{X^2+Y^2}\,C_0
      }.
$$

The scan gives

$$
    \max R_1=\frac12,
    \qquad
    \max R_2=\frac12,
    \qquad
    \max R_3=\frac38,
$$

all attained in the $q\to0$ limit. The first bound can also be shown directly.
The identity

$$
    qM_2=2M_1-e^{-q}
$$

reduces the angular maximization to $M_1/M_0$, and the decreasing weight
$e^{-qz}$ implies $M_1/M_0\leq1/2$.

The second- and third-order maxima above are numerical calibration of the
analytic coefficients, not yet formal interval bounds. A conservative
implementation can replace $3/8$ by one until an interval proof or validated
high-precision sweep is part of the test suite.

## 4. Error of the present round replacement

The current uncoupled round branch uses

$$
    \bar\sigma=\frac{\sigma_1+\sigma_2}{2}.
$$

At the origin its linear gradient is $1/\bar\sigma^2$. Comparing it with the
exact elliptical gradients gives

$$
    \frac{K_{x,\mathrm{round}}/x}{K_{x,\mathrm{exact}}/x}
      =1+\delta_\sigma,
    \qquad
    \frac{K_{y,\mathrm{round}}/y}{K_{y,\mathrm{exact}}/y}
      =1-\delta_\sigma.
$$

Therefore the round replacement has an exact relative core-gradient error

$$
    E_{\mathrm{round,core}}=\delta_\sigma.
$$

The same statement applies to the on-axis transverse Hessian because the
Hessian there is the linear force gradient. Thus a hard switch at
$\delta_\sigma=\tau$ has an exact-arithmetic mismatch of order $\tau$ in the
most sensitive core quantity.

For the present value $\tau=10^{-10}$, the model-side force mismatch is only
about $10^{-10}$. The branch itself therefore does not create a large
value discontinuity in exact arithmetic. It does, however, discard the
first derivative with respect to beam anisotropy on the round side, so it is
not a continuously differentiable representation of a changing covariance.

## 5. Conditioning of the elliptical formula

The Bassetti-Erskine representation contains

$$
    \Delta_\lambda
      =
      \lambda_1-\lambda_2
      =
      2s^2\eta
$$

inside both a square root and the Faddeeva arguments. Forming the difference of
two nearly equal variances introduces the first-order condition estimate

$$
    \frac{|\delta\Delta_\lambda|}{|\Delta_\lambda|}
      \sim
      C_\Delta\frac{\varepsilon_T}{|\eta|},
$$

where $\varepsilon_T$ is machine epsilon for the arithmetic type and
$C_\Delta$ includes the preceding covariance/eigenvalue operations. The
resulting field/Hessian error has the model

$$
    E_{\mathrm{BE},\eta}
      \sim
      C_{\mathrm{BE}}\frac{\varepsilon_T}{|\eta|}
      \simeq
      C_{\mathrm{BE}}
      \frac{\varepsilon_T}{2\delta_\sigma}.
$$

$C_{\mathrm{BE}}$ is not a universal mathematical constant. It depends on:

- how the covariance eigenvalues are formed;
- the Faddeeva implementation;
- Float32 versus Float64 arithmetic;
- CPU versus CUDA evaluation; and
- whether force, Hessian, or longitudinal-kick error is measured.

It must be calibrated against the fixed-interval reference of Section 2.

### 5.1 Separate near-axis cancellation

There is a second conditioning variable. At fixed nonzero $\eta$, the two
Faddeeva terms both approach one as the field point approaches the origin,
while their difference is proportional to the radius. A local estimate is

$$
    E_{\mathrm{BE},r}
      \sim
      C_r
      \frac{\varepsilon_T}{R\sqrt{|\eta|}},
    \qquad
    R=\frac{\sqrt{x^2+y^2}}{s},
$$

for pointwise relative force error. No threshold depending only on $\eta$ can
provide uniform pointwise relative accuracy as $R\to0$, because the exact
force itself vanishes there.

This does not mean the absolute error diverges. In units of the natural field
scale $1/s$, the corresponding estimate is

$$
    s\,|\delta\mathbf K|
      \sim
      C_r\frac{\varepsilon_T}{\sqrt{|\eta|}}.
$$

Nevertheless, accurate core focusing and Hessians require a separate
near-axis series or a unified near-round expansion. Adjusting only the
aspect-ratio threshold cannot cure every cancellation in the raw
Bassetti-Erskine expression.

## 6. Error-balanced switch for the current round-only branch

First ignore the separate radial term by assuming that the elliptical core is
evaluated stably or that the acceptance metric is scale-aware. The leading
errors at a switch expressed in $\delta_\sigma$ are

$$
    E_{\mathrm{round}}
      \simeq\delta_\sigma,
    \qquad
    E_{\mathrm{BE}}
      \simeq
      C_{\mathrm{BE}}
      \frac{\varepsilon_T}{2\delta_\sigma}.
$$

Balancing them gives

$$
\boxed{
    \delta_{\sigma,*}^{(0)}
      =
      \sqrt{\frac{C_{\mathrm{BE}}\varepsilon_T}{2}}.
}
$$

For the central estimate $C_{\mathrm{BE}}=1$:

| arithmetic | $\varepsilon_T$ | $\delta_{\sigma,*}^{(0)}$ | balanced relative error |
|---|---:|---:|---:|
| Float64 | $2.2204\times10^{-16}$ | $1.05\times10^{-8}$ | $1.05\times10^{-8}$ |
| Float32 | $1.1921\times10^{-7}$ | $2.44\times10^{-4}$ | $2.44\times10^{-4}$ |

These are estimates, not replacement constants. They show the scaling:

- A fixed $10^{-10}$ threshold is much smaller than the error-balanced
  Float64 estimate.
- In Float32, $10^{-10}$ is below the resolution at which two order-one beam
  sizes can normally be distinguished. It effectively selects the round
  branch only after the sizes have already rounded to equality.
- A round-only evaluator cannot simultaneously make its model error and the
  near-round elliptical conditioning error close to machine epsilon. Its best
  balanced error scales as $\sqrt{\varepsilon_T}$.

For a requested relative tolerance $\tau$, an overlap exists only if

$$
    \frac{C_{\mathrm{BE}}\varepsilon_T}{2\tau}
      \leq\delta_\sigma
      \leq\tau.
$$

If this interval is empty, changing the hard threshold cannot meet the
tolerance; a higher-order expansion or a better-conditioned exact evaluation
is required.

## 7. Error-balanced switch with a second-order expansion

Retaining $C_0$, $C_1$, and $C_2$ makes the first omitted force term
$\eta^3C_3$. Using the calibrated core coefficient $3/8$,

$$
    E_{\mathrm{series},2}
      \simeq
      \frac38|\eta|^3
      \simeq
      3\delta_\sigma^3.
$$

Balance this against the same elliptical conditioning estimate:

$$
    3\delta_\sigma^3
      =
      C_{\mathrm{BE}}
      \frac{\varepsilon_T}{2\delta_\sigma}.
$$

The resulting switch estimate is

$$
\boxed{
    \delta_{\sigma,*}^{(2)}
      =
      \left(
        \frac{C_{\mathrm{BE}}\varepsilon_T}{6}
      \right)^{1/4}.
}
$$

For $C_{\mathrm{BE}}=1$:

| arithmetic | $\delta_{\sigma,*}^{(2)}$ | estimated transition error |
|---|---:|---:|
| Float64 | $7.80\times10^{-5}$ | $1.42\times10^{-12}$ |
| Float32 | $1.19\times10^{-2}$ | $5.02\times10^{-6}$ |

The larger switch value is desirable here. It means that the stable expansion
is used throughout the ill-conditioned overlap while retaining the leading
elliptic corrections. The transition error is much smaller than that of the
round-only balance.

More generally, suppose a near-round expansion retains powers through
$\eta^p$ and its first omitted relative coefficient is bounded by $C_s$:

$$
    E_{\mathrm{series},p}
      \leq C_s|\eta|^{p+1}.
$$

Balancing it with $C_{\mathrm{BE}}\varepsilon_T/|\eta|$ gives

$$
\boxed{
    |\eta_*|
      =
      \left(
        \frac{C_{\mathrm{BE}}\varepsilon_T}{C_s}
      \right)^{1/(p+2)}.
}
$$

This is the standard error-balance rule for a removable singularity: switch
where truncation error and conditioning-amplified roundoff are comparable.

## 8. Hard switching versus smooth blending

A hard algorithmic switch is not inherently a physical discontinuity. Standard
mathematical libraries use hard switches among power series, rational
approximations, and asymptotic expansions. The relevant requirement is

$$
    |\mathbf K_{\mathrm{left}}-\mathbf K_{\mathrm{right}}|
      \leq \text{accepted error}
$$

throughout an overlap interval. At an error-balanced switch, the jump is bounded
approximately by the sum of the two representation errors.

A smooth blend can be used when continuity with respect to changing covariance
is itself required. Let $\eta_0<\eta_1$, define

$$
    t
      =
      \operatorname{clamp}
      \left(
        \frac{|\eta|-\eta_0}{\eta_1-\eta_0},
        0,1
      \right),
$$

and use the quintic smoothstep

$$
    w(t)=6t^5-15t^4+10t^3.
$$

The blend must be made at the potential level:

$$
    U=(1-w)U_{\mathrm{series}}+wU_{\mathrm{BE}}.
$$

Both potentials must use the same covariance-independent gauge. Otherwise
$U_{\mathrm{BE}}-U_{\mathrm{series}}$ contains an arbitrary offset and the
longitudinal chain term below is not physically defined.

For the six-dimensional map, $\eta$ changes with collision position through
the transported covariance. Its longitudinal derivative therefore contains
the chain-rule term

$$
\begin{aligned}
    U_u
      ={}&
      (1-w)U_{\mathrm{series},u}
      +wU_{\mathrm{BE},u}\\
      &+
      w_\eta\eta_u
      (U_{\mathrm{BE}}-U_{\mathrm{series}}).
\end{aligned}
$$

Blending transverse forces or Hessians independently while omitting this term
generally breaks the potential/Hessian relationship used by the symplectic
longitudinal kick.

When the two formulas already agree below the requested tolerance, a hard
switch is simpler and preferable. Blending does not repair an inaccurate
formula; it only spreads its error over an interval.

## 9. Recommended Octopus decision procedure

The following sequence should be used before changing
`ROUND_BEAM_THRESHOLD`.

1. Use the invariant $\eta$ definition for both uncoupled and coupled
   covariance paths.
2. Implement the fixed-interval integral in high precision as the reference,
   not as the production evaluator.
3. Measure, separately for CPU/CUDA and Float32/Float64,

   $$
       C_{\mathrm{BE}}
         =
         \max
         \left(
           E_{\mathrm{BE}}
           \frac{|\eta|}{\varepsilon_T}
         \right)
   $$

   over the declared field domain, while separately recording the radial
   cancellation of Section 5.1.
4. If retaining only the round limit, begin the calibration near
   $\delta_\sigma\sim10^{-8}$ for Float64 and
   $\delta_\sigma\sim2\times10^{-4}$ for Float32, then insert the measured
   $C_{\mathrm{BE}}$ into Section 6.
5. Prefer a second-order near-round evaluator. Begin its calibration near
   $\delta_\sigma\sim10^{-4}$ for Float64 and
   $\delta_\sigma\sim10^{-2}$ for Float32, then use the measured
   $C_{\mathrm{BE}}$ and a validated bound on $C_3$ in Section 7.
6. Add a separate near-axis expansion if the raw elliptical evaluator remains
   inaccurate at small $R$ outside the near-round interval.
7. Derive force and Hessian coefficients from the same integral expansion.
   Validate the complete longitudinal kick, not only the transverse field.
8. Use a hard switch if value and Hessian mismatches are below the target.
   Use potential-level blending only when covariance-derivative continuity is
   an explicit requirement.

The values in steps 4 and 5 are centers for validation scans. They are not
universal constants to be copied into source code.

## 10. Required validation

A production change should sweep:

- $\eta$ logarithmically from exact roundness through at least $10^{-1}$;
- radius from the linear core through the far-field tail;
- polar angle over one quadrant;
- Float32 and Float64;
- CPU and every CUDA Faddeeva path; and
- force, potential differences, Hessian, and the complete longitudinal kick.

At each candidate transition, test:

1. error against high-precision quadrature of Section 2;
2. the value jump immediately below and above the switch;
3. the Hessian jump and finite-difference force derivatives;
4. covariance-transport derivatives through the switch;
5. finite-difference six-dimensional symplecticity; and
6. repeated crossing of the threshold as the transported covariance changes.

The validation report should state its normalization. Pointwise relative force
error is singular at the origin because the exact force vanishes. Core-gradient
error, natural-scale absolute error, and Hessian error remain meaningful there.

## 11. Conclusion

The current $10^{-10}$ comparison creates only an order-$10^{-10}$ ideal
round-model mismatch, but it is not derived from floating-point conditioning
and cannot serve Float32 and Float64 equally.

For a round-only branch, the central error-balance estimate is

$$
    \delta_{\sigma,*}^{(0)}
      \sim
      \sqrt{\frac{C_{\mathrm{BE}}\varepsilon_T}{2}}.
$$

For a second-order near-round expansion, it improves to

$$
    \delta_{\sigma,*}^{(2)}
      \sim
      \left(
        \frac{C_{\mathrm{BE}}\varepsilon_T}{6}
      \right)^{1/4}.
$$

The second formula is the recommended design direction. It preserves the
leading elliptic physics, gives a broad overlap with the exact formula, and can
make the hard algorithmic transition smaller than the scientific tolerance.
The final numerical threshold must come from the measured
$C_{\mathrm{BE}}$ for each precision/backend and from a validated near-axis
policy.
