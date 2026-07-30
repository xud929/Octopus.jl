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

The procedure derived here is implemented in
`src/elements/strong_beam.jl` and its CUDA counterpart in
`src/track/strong_beam_track.jl`. The production evaluator now uses:

- the invariant variance anisotropy $\eta$;
- a third-order near-round potential expansion;
- a precision-scaled overlap interval;
- a quintic potential-level blend with the longitudinal chain term; and
- a separate error-balanced near-axis expansion for the elliptical evaluator.

The former fixed `ROUND_BEAM_THRESHOLD = 1e-10` comparison has been removed.
Section 10 records the reproducible numerical validation performed after the
implementation.

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

The size-based quantity used by the former uncoupled implementation was

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

The former code used $\delta_\sigma$ in the uncoupled field evaluator but
$\eta$ in the coupled-covariance branch. The implementation now uses $\eta$ in
both paths, so rotation and coupling do not change the transition criterion.

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

### 3.1 Potential expansion and covariance response

The six-dimensional map requires more than the transverse force. It requires
the derivative of the same approximate potential with respect to the
transported covariance. Let $v=s^2$. With a covariance-independent gauge, the
near-round potential can be written

$$
    U_{\mathrm{series}}
      =
      U_0+\eta U_1+\eta^2U_2+\eta^3U_3,
$$

where

$$
    U_0=-\operatorname{Ein}(q)-\log v+C,
    \qquad
    \operatorname{Ein}(q)
      =
      \int_0^q\frac{1-e^{-t}}{t}\,dt,
$$

and

$$
\begin{aligned}
    U_1={}&d_rM_1,\\
    U_2={}&\frac12M_1-qM_2+\frac{d_r^2}{2}M_3,\\
    U_3={}&\frac{3d_r}{2}M_3-d_rqM_4+\frac{d_r^3}{6}M_5.
\end{aligned}
$$

Taking $-\nabla U_{\mathrm{series}}$ gives the force coefficients
$C_0$ through $C_3$ above. For the covariance derivative, define

$$
    V_n=v\frac{\partial U_n}{\partial v}
$$

at fixed $(x,y,\eta)$. The implemented coefficients are

$$
\begin{aligned}
    V_1={}&d_r(qM_2-M_1),\\
    V_2={}&
      \frac{3q}{2}M_2-(q^2+d_r^2)M_3
      +\frac{qd_r^2}{2}M_4,\\
    V_3={}&
      -\frac{3d_r}{2}M_3+\frac{7d_rq}{2}M_4\\
      &-\left(d_rq^2+\frac{d_r^3}{2}\right)M_5
      +\frac{d_r^3q}{6}M_6.
\end{aligned}
$$

Thus

$$
    vU_v
      =
      -e^{-q}+\eta V_1+\eta^2V_2+\eta^3V_3,
$$

$$
    U_\eta=U_1+2\eta U_2+3\eta^2U_3.
$$

Because

$$
    \frac{\partial\eta}{\partial\lambda_1}
      =
      \frac{1-\eta}{2v},
    \qquad
    \frac{\partial\eta}{\partial\lambda_2}
      =
      -\frac{1+\eta}{2v},
$$

the two principal covariance responses used by the longitudinal kick are

$$
\boxed{
\begin{aligned}
    \mathcal H_1
      &=2\frac{\partial U_{\mathrm{series}}}{\partial\lambda_1}
       =U_v+\frac{1-\eta}{v}U_\eta,\\
    \mathcal H_2
      &=2\frac{\partial U_{\mathrm{series}}}{\partial\lambda_2}
       =U_v-\frac{1+\eta}{v}U_\eta.
\end{aligned}
}
$$

For the exact Gaussian potential, $\mathcal H_i$ equals the corresponding
spatial potential Hessian component by the Gaussian heat identity. For the
truncated potential, it is important to evaluate the displayed covariance
derivative directly. Substituting an independently truncated spatial Hessian
would not, in general, be the derivative of the same approximate potential.

This is why the implementation retains $U_3$ even though the original switch
estimate was described as a second-order force expansion. Differentiating with
respect to covariance lowers the usable series order by one: retaining only
$U_0,U_1,U_2$ leaves a general $O(\eta^2)$ covariance-response error.
Retaining $U_3$ makes the first omitted response term $O(\eta^3)$ and preserves
the potential basis of the six-dimensional map.

## 4. Error of the former round replacement

The former uncoupled round branch used

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

For the former value $\tau=10^{-10}$, the model-side force mismatch was only
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

### 5.2 Implemented near-axis evaluator

The production elliptical evaluator now uses a fifth-degree radial expansion
when the Faddeeva subtraction is less accurate. Define

$$
    G_x
      =
      \int_0^\infty
      \frac{dt}{
        (\lambda_1+t)^{3/2}(\lambda_2+t)^{1/2}
      }
      =
      \frac{2}{\sigma_1(\sigma_1+\sigma_2)}
$$

and

$$
    J^{(x)}_{mn}
      =
      \int_0^\infty
      \frac{dt}{
        (\lambda_1+t)^{3/2+m}
        (\lambda_2+t)^{1/2+n}
      }.
$$

All required coefficients are rational functions of $\sigma_1,\sigma_2$ and
are generated by

$$
    J^{(x)}_{mn}
      =
      \frac{
        (-1)^{m+n}
        \partial_{\lambda_1}^m
        \partial_{\lambda_2}^nG_x
      }{
        (3/2)_m(1/2)_n
      }.
$$

Expanding the Gaussian factor gives

$$
\begin{aligned}
    K_x
      =x\bigg[
        &G_x-\frac{x^2}{2}J^{(x)}_{10}
             -\frac{y^2}{2}J^{(x)}_{01}\\
        &+\frac{x^4}{8}J^{(x)}_{20}
             +\frac{x^2y^2}{4}J^{(x)}_{11}
             +\frac{y^4}{8}J^{(x)}_{02}
      \bigg]
      +O(\rho^7/s),
\end{aligned}
$$

where

$$
    \rho^2
      =
      \frac{x^2}{\sigma_1^2}
      +
      \frac{y^2}{\sigma_2^2}.
$$

$K_y$ follows by exchanging
$(x,\sigma_1)\leftrightarrow(y,\sigma_2)$. The principal response components
are differentiated from this same polynomial.

The force has $O(\rho^6)$ relative truncation error, while the raw Faddeeva
difference has the estimate
$O(\varepsilon_T/(\rho\sqrt{\eta}))$. Balancing them gives the implemented
test

$$
\boxed{
    \rho^7
      \leq
      \frac{\varepsilon_T}{\sqrt{\eta}}.
}
$$

This is a separate representation switch, independent of the near-round
blend. It restores the exact flat-beam core gradients in Section 3 and avoids
the several-parts-per-million core-gradient loss observed from raw Faddeeva
subtraction near the Float64 anisotropy boundary.

## 6. Historical round-only switch estimate

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

## 7. Implemented third-order potential transition

The original estimate retained force terms through $\eta^2$, so the first
omitted force coefficient was $C_3$ and its calibrated core magnitude was
$3/8$. Section 3.1 shows why the six-dimensional implementation must instead
retain the potential and force through $\eta^3$: the first omitted covariance
response is still $O(\eta^3)$ because a covariance derivative lowers the
potential order by one. Its core coefficient is again $3/8$.

The dense fixed-interval calibration gives
$C_{\mathrm{BE}}=64$ for Float64 and
$C_{\mathrm{BE}}=8$ for Float32 over the declared field domain. Balance

$$
    E_{\mathrm{series,response}}
      \simeq
      \frac38|\eta|^3
$$

against

$$
    E_{\mathrm{BE},\eta}
      \simeq
      C_{\mathrm{BE}}\frac{\varepsilon_T}{|\eta|}.
$$

The implemented outer boundary is therefore

$$
\boxed{
    \eta_*
      =
      \left(
        \frac{8C_{\mathrm{BE}}\varepsilon_T}{3}
      \right)^{1/4}.
}
$$

In the size-based convention this is

$$
    \delta_{\sigma,*}
      =
      \frac{\eta_*}{1+\sqrt{1-\eta_*^2}}
      \simeq
      \left(\frac{C_{\mathrm{BE}}\varepsilon_T}{6}\right)^{1/4}.
$$

The smooth overlap begins at $\eta_0=\eta_*/2$ and ends at
$\eta_1=\eta_*$. The values are computed from `eps(T)` and the measured
conditioning factor rather than stored as decimal thresholds:

| arithmetic | $\eta_0$ | $\eta_1$ | $\delta_{\sigma,0}$ | $\delta_{\sigma,1}$ | estimated response error at $\eta_1$ |
|---|---:|---:|---:|---:|---:|
| Float64 | $2.2061\times10^{-4}$ | $4.4121\times10^{-4}$ | $1.1030\times10^{-4}$ | $2.2061\times10^{-4}$ | $3.2209\times10^{-11}$ |
| Float32 | $1.9967\times10^{-2}$ | $3.9934\times10^{-2}$ | $9.9845\times10^{-3}$ | $1.9975\times10^{-2}$ | $2.3881\times10^{-5}$ |

The factors 64 and 8 are conservative rounded calibration values. At the
resulting outer boundaries, the dense validation sweep measures effective
conditioning factors $61.937$ for Float64 and $4.948$ for Float32. The
corresponding series and elliptical response errors overlap within the expected
order-one calibration uncertainty.

This calibration must use a dense field grid. An earlier sparse set of
conventional radii measured factors $9.216$ and $1.291$, but a follow-up sweep
over 513 values of $q$ and 65 angles found narrow Faddeeva-error peaks that the
sparse grid missed. Those preliminary factors are not used by the
implementation.

The larger boundary compared with a round-only replacement is desirable. The
stable expansion covers the ill-conditioned region while retaining elliptic
physics, and the exact formula is not used until its conditioning and the
series response error are comparable.

### 7.1 Potential residual used by the blend

The blend chain term needs
$\Delta U=U_{\mathrm{BE}}-U_{\mathrm{series}}$ in a common gauge. Directly
subtracting two order-one potentials would lose the small residual. The
implementation evaluates its analytic expansion through $\eta^6$:

$$
    \Delta U
      =
      \eta^4\left(U_4+\eta U_5+\eta^2U_6\right)
      +O(\eta^7),
$$

with

$$
\begin{aligned}
    U_4={}&
      \frac38M_3-\frac{3q}{2}M_4
      +\frac{5d_r^2+2q^2}{4}M_5
      -\frac{d_r^2q}{2}M_6
      +\frac{d_r^4}{24}M_7,\\
    U_5={}&
      \frac{15d_r}{8}M_5-\frac{5d_rq}{2}M_6
      +\frac{d_r(7d_r^2+6q^2)}{12}M_7\\
      &-\frac{d_r^3q}{6}M_8
      +\frac{d_r^5}{120}M_9,\\
    U_6={}&
      \frac5{16}M_5-\frac{15q}{8}M_6
      +\frac{5(7d_r^2+4q^2)}{16}M_7\\
      &-\frac{q(21d_r^2+2q^2)}{12}M_8
      +\frac{d_r^2(3d_r^2+4q^2)}{16}M_9\\
      &-\frac{d_r^4q}{24}M_{10}
      +\frac{d_r^6}{720}M_{11}.
\end{aligned}
$$

At the implemented boundaries, the omitted contribution to the blend chain
term is below the balanced response error for both Float32 and Float64.

For a general response expansion with leading error
$C_s|\eta|^p$, balancing against
$C_{\mathrm{BE}}\varepsilon_T/|\eta|$ gives

$$
\boxed{
    |\eta_*|
      =
      \left(
        \frac{C_{\mathrm{BE}}\varepsilon_T}{C_s}
      \right)^{1/(p+1)}.
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

This is the implemented construction with
$\eta_0=\eta_*/2$ and $\eta_1=\eta_*$. In the principal covariance frame, the
transverse force is

$$
    \mathbf K
      =
      (1-w)\mathbf K_{\mathrm{series}}
      +w\mathbf K_{\mathrm{BE}}.
$$

The two covariance responses are

$$
\boxed{
\begin{aligned}
    \mathcal H_1={}&
      (1-w)\mathcal H_{1,\mathrm{series}}
      +w\mathcal H_{1,\mathrm{BE}}
      +\frac{1-\eta}{v}w_\eta\Delta U,\\
    \mathcal H_2={}&
      (1-w)\mathcal H_{2,\mathrm{series}}
      +w\mathcal H_{2,\mathrm{BE}}
      -\frac{1+\eta}{v}w_\eta\Delta U.
\end{aligned}
}
$$

The quintic has $w'=w''=0$ at both endpoints. The exact-arithmetic potential
is consequently $C^2$ across each representation boundary, and its force and
first covariance derivative are continuous. The numerical endpoint experiment
in Section 10 measures the finite-precision residual.

Blending transverse forces or Hessians independently while omitting this term
generally breaks the potential/Hessian relationship used by the symplectic
longitudinal kick.

For a coupled covariance, the implementation also avoids separately forming
the singular product $\theta_u(K_x y-K_y x)$. It evaluates

$$
    \frac{(a-d)b_u-b(a_u-d_u)}{D}
    \frac{K_x y-K_y x}{D},
$$

whose two factors have finite round limits. In the series region the second
factor is evaluated in a cancellation-free form. At $D=0$ the invariant
laboratory-frame round response is used.

Blending does not repair an inaccurate component formula; it only spreads its
error over an interval. That is why the separate near-axis evaluator in
Section 5.2 remains necessary.

## 9. Implemented Octopus decision procedure

For every positive pair of principal beam sizes, the CPU and CUDA paths now
apply the same sequence:

1. Compute
   $v=(\lambda_1+\lambda_2)/2$ and
   $\eta=(\lambda_1-\lambda_2)/(\lambda_1+\lambda_2)$.
2. At exact roundness, use the stable round formula based on `expm1`.
3. Compute
   $\eta_1=(8C_{\mathrm{BE}}(T)\operatorname{eps}(T)/3)^{1/4}$ and
   $\eta_0=\eta_1/2$.
   The calibrated factors are $C_{\mathrm{BE}}(\mathrm{Float64})=64$ and
   $C_{\mathrm{BE}}(\mathrm{Float32})=8$.
4. For $\eta\leq\eta_0$, use the third-order potential expansion.
5. For $\eta_0<\eta<\eta_1$, blend the series and Bassetti-Erskine potentials
   with the quintic weight and include the $\Delta U\,w_\eta$ covariance chain
   term.
6. For $\eta\geq\eta_1$, use Bassetti-Erskine.
7. Within every elliptical Bassetti-Erskine evaluation, replace the Faddeeva
   difference by the fifth-degree radial expansion when
   $\rho^7\leq\varepsilon_T/\sqrt{\eta}$.
8. For a coupled covariance, rotate the force through the principal frame but
   contract the longitudinal response in the stable invariant form described
   in Section 8.

The moment integrals use their power series for $q\leq2$, with 17 terms for
`Float32` and 25 terms for `Float64`, and the upward recurrence for $q>2$. At
$q=2$, the 17-term series is already at the `Float32` rounding floor. This
avoids cancellation near the origin without evaluating terms that the working
precision cannot retain. All constants are converted to the input arithmetic
type, so Float32 does not silently promote to Float64 in either the CPU or CUDA
elliptical path.

The shared procedure is consumed by weak-strong tracking, the soft-Gaussian
strong-strong solver, and the analytic Gaussian add-back in both CPU and CUDA
GaussianPIC kernels. The GaussianPIC longitudinal path requests force and
covariance response from one call so its two components cannot select
different transition branches.

## 10. Validation and numerical experiment

The validation domain for this production change includes:

- selected $\eta$ values from exact roundness through $0.5$, with explicit
  samples below, inside, and above both blend endpoints;
- $q=R^2/2$ from the linear core through $8$;
- polar angle over one quadrant;
- Float32 and Float64;
- CPU and CUDA evaluators; and
- force, principal covariance response, core gradients, and the complete
  six-dimensional map.

The experiment checks:

1. error against independent 96-point quadrature of Section 2;
2. extrapolated value and first-derivative gaps at both endpoints;
3. the covariance response through the switch;
4. exact flat-beam core gradients;
5. finite-difference six-dimensional symplecticity; and
6. CPU/CUDA parity.

The validation report should state its normalization. Pointwise relative force
error is singular at the origin because the exact force vanishes. Core-gradient
error, natural-scale absolute error, and Hessian error remain meaningful there.

### 10.1 Reproducible transition sweep

The experiment is implemented in
`validation/near_round_gaussian_transition.jl` and can be repeated with

```bash
julia --project=. validation/near_round_gaussian_transition.jl
```

The reference is the fixed-interval integral of Section 2 evaluated with
96-point Gauss-Legendre quadrature. The sweep uses

- $\eta=0$, points below, inside, and above the transition, then
  $10^{-3},10^{-2},10^{-1},0.5$;
- three core values of $q$ down to $5\times10^{-13}$ plus 513 uniformly
  spaced values from $1/64$ through $8$;
- 65 angles from $0$ through $\pi/2$;
- Float32 and Float64; and
- the CPU evaluator plus CUDA parity when a CUDA device is available.

With $s=1$, the natural force and response scales are also one. The run on
2026-07-30 produced:

| metric | Float32 | Float64 |
|---|---:|---:|
| transition interval $[\eta_0,\eta_1]$ | $[1.9967\times10^{-2},\,3.9934\times10^{-2}]$ | $[2.2061\times10^{-4},\,4.4121\times10^{-4}]$ |
| maximum transition force relative error | $4.7557\times10^{-6}$ | $6.1096\times10^{-12}$ |
| maximum transition force natural-scale error | $8.4271\times10^{-7}$ | $6.3707\times10^{-14}$ |
| maximum transition response natural-scale error | $1.4771\times10^{-5}$ | $3.1170\times10^{-11}$ |
| maximum core-gradient relative error | $1.1921\times10^{-7}$ | $2.2204\times10^{-16}$ |
| finite-difference 6D symplectic residual | not evaluated | $1.6001\times10^{-10}$ |
| maximum CPU/CUDA natural-scale difference | $1.0541\times10^{-5}$ | $1.9150\times10^{-11}$ |

The response relative-error maxima were
$1.7781\times10^{-3}$ for Float32 and
$1.2449\times10^{-8}$ for Float64. Both occur where the response
norm is small, so the natural-scale errors in the table are the appropriate
conditioning metric.

### 10.2 Endpoint continuity experiment

At each endpoint, the script samples at
$\eta_b-2h,\eta_b-h,\eta_b,\eta_b+h,\eta_b+2h$ with
$h=0.01\eta_b$. Linear extrapolation from each side estimates a possible value
gap. Second-order one-sided differences estimate the first-derivative mismatch.
These are finite-precision upper bounds, not symbolic jumps; the construction
in Section 8 has zero exact-arithmetic value and first-derivative jump.

The largest natural-scale estimates over the radius-angle grid were:

| arithmetic | endpoint | force value gap | response value gap | $\eta_b$-scaled force derivative gap | $\eta_b$-scaled response derivative gap |
|---|---|---:|---:|---:|---:|
| Float32 | inner | $7.7843\times10^{-7}$ | $6.9510\times10^{-7}$ | $7.9523\times10^{-5}$ | $7.8000\times10^{-5}$ |
| Float32 | outer | $2.9019\times10^{-6}$ | $2.2866\times10^{-5}$ | $3.7581\times10^{-4}$ | $4.5829\times10^{-3}$ |
| Float64 | inner | $1.5779\times10^{-15}$ | $1.2439\times10^{-14}$ | $1.5682\times10^{-13}$ | $2.2658\times10^{-13}$ |
| Float64 | outer | $1.6606\times10^{-13}$ | $4.6786\times10^{-11}$ | $1.6423\times10^{-11}$ | $4.6862\times10^{-9}$ |

The outer response is the least smooth quantity in finite precision because it
contains the conditioned Bassetti-Erskine covariance response. Its Float32
value-gap estimate remains $2.3\times10^{-5}$ in natural units, while the
transverse force, which drives tracking directly, remains below
$3.0\times10^{-6}$. The exact core-gradient checks demonstrate that these
numbers are not hiding a near-axis failure.

## 11. Conclusion

The former $10^{-10}$ comparison created only an order-$10^{-10}$ ideal
round-model mismatch, but it was not derived from floating-point conditioning
and could not serve Float32 and Float64 equally.

For a round-only branch, the central error-balance estimate is

$$
    \delta_{\sigma,*}^{(0)}
      \sim
      \sqrt{\frac{C_{\mathrm{BE}}\varepsilon_T}{2}}.
$$

For the implemented third-order potential expansion, the covariance-response
balance is

$$
    \delta_{\sigma,*}
      \sim
      \left(
        \frac{C_{\mathrm{BE}}\varepsilon_T}{6}
      \right)^{1/4}.
$$

The code evaluates the equivalent invariant boundary directly as
$\eta_*=(8C_{\mathrm{BE}}\varepsilon_T/3)^{1/4}$ and blends from
$\eta_*/2$ to $\eta_*$.
It preserves elliptic physics through third order, keeps the transverse force
continuous across the overlap, includes the covariance chain term required by
the six-dimensional map, and uses a separate radial series where Faddeeva
subtraction is inaccurate.

The validation shows transition-force errors of
$6.2\times10^{-12}$ or less in Float64 and
$4.8\times10^{-6}$ or less in Float32 over the declared scan, with finite core
gradients and CPU/CUDA agreement at the arithmetic-appropriate scale. The
Float32 outer covariance response remains the limiting continuity quantity and
should be remeasured if the CUDA Faddeeva approximation, expansion order, or
declared scientific tolerance changes.
