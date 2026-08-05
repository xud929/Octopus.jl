# Longitudinal Slicing of a Gaussian Source Bunch

This note derives the rules that decide **where to put longitudinal slices and
what charge to give them** when a continuous Gaussian source bunch is replaced
by a finite train of thin slices.

It is the companion to two existing notes and does not repeat them:

- [Weak–Strong Six-Dimensional Source Model](weak_strong_6d_model.md) defines
  *what one slice is* — the conditional transverse Gaussian at a given $z$, and
  the finite-bin correction that the delta-slice approximation drops (Section 4
  there).
- [Synchro-Beam Longitudinal Kick](beam_beam_longitudinal_kick.md) defines
  *what a slice does* — the virtual drift to the collision point, the kick, and
  the longitudinal terms.

The present note answers only the placement question. The reference is
Furman, Zholents, Chen and Shatilov [1], which compares five prescriptions;
Section 9 covers rules that postdate or fall outside that note.

## 1. Slicing is a quadrature rule

The longitudinal line density of the source bunch is

$$
    \hat\rho_\ell(z)
      =\frac{1}{\sqrt{2\pi}\,\sigma_z}\exp\!\left(-\frac{z^2}{2\sigma_z^2}\right),
    \qquad
    \int\hat\rho_\ell(z)\,\mathrm dz=1,
$$

where the caret marks unit normalization. A tracked particle receives the
accumulated effect of the whole source,

$$
    \Delta\mathcal K=\int \hat\rho_\ell(z)\,\mathcal K(z)\,\mathrm dz ,
$$

where $\mathcal K(z)$ is the kick contributed by the source charge at
longitudinal coordinate $z$, evaluated at the collision point that $z$ implies.
Simulation replaces the continuum by a weighted delta train

$$
    \hat\rho_\ell(z)\;\longrightarrow\;
    \hat\rho_s(z)\equiv\sum_{k=-L}^{L}w_k\,\delta(z-z_k),
    \qquad N_s\equiv 2L+1 ,
$$

so that

$$
    \Delta\mathcal K\;\approx\;\sum_{k=-L}^{L}w_k\,\mathcal K(z_k).
$$

**A slicing rule is therefore a quadrature rule for the Gaussian weight
function.** This framing is worth stating explicitly because it fixes what
"optimal" can mean: a rule is optimal only with respect to a class of
integrands $\mathcal K$. Furman's five rules approximate the *density*; a
Gauss–Hermite rule (Section 9.1) matches *polynomial moments*; neither is
tailored to the actual $\mathcal K$, which is not polynomial in $z$ — it carries
the drifted source size $\sigma(s_c)$ with $s_c=(z_+-z_k)/2$ and therefore an
hourglass factor of the form $\big(1+(s_c/\beta^*)^2\big)^{-1/2}$.

Three constraints are imposed throughout. The bunch is longitudinally
symmetric, so

$$
    z_{-k}=-z_k,\qquad w_{-k}=w_k ,
$$

and the total charge must be preserved,

$$
    \sum_{k=-L}^{L}w_k=1 .
$$

$N_s$ is taken **odd** so that one slice sits at the bunch centre; Section 8
covers even $N_s$. The thin-lens limit is $N_s=1$, $z_0=0$, $w_0=1$.

## 2. Standard-normal building blocks

Work in the scaled coordinate $\zeta=z/\sigma_z$ and write

$$
    \varphi(\zeta)=\frac{1}{\sqrt{2\pi}}e^{-\zeta^2/2},
    \qquad
    \Phi(\zeta)=\int_{-\infty}^{\zeta}\varphi(t)\,\mathrm dt
             =\frac12\left[1+\operatorname{erf}\!\left(\frac{\zeta}{\sqrt2}\right)\right].
$$

The quantile function follows by inversion,

$$
    \Phi^{-1}(p)=\sqrt2\,\operatorname{erf}^{-1}(2p-1).
$$

Two identities carry all the derivations below. The first is the definition of
a slice charge,

$$
    \int_a^b\varphi(\zeta)\,\mathrm d\zeta=\Phi(b)-\Phi(a).
    \tag{I1}
$$

The second follows from $\varphi'(\zeta)=-\zeta\varphi(\zeta)$ and is the
workhorse for every centroid formula:

$$
    \int_a^b\zeta\,\varphi(\zeta)\,\mathrm d\zeta
      =-\big[\varphi(\zeta)\big]_a^b
      =\varphi(a)-\varphi(b).
    \tag{I2}
$$

Combining them, the **centre of charge of a slice** spanning $[a,b]$ is

$$
    \langle\zeta\rangle_{[a,b]}
      =\frac{\varphi(a)-\varphi(b)}{\Phi(b)-\Phi(a)} .
    \tag{I3}
$$

A third quantity is used as a diagnostic. The delta train can never reproduce
the second moment exactly, because it discards the variance *inside* each
slice:

$$
    \sum_k w_k z_k^2
      =\sigma_z^2-\sum_k w_k\operatorname{Var}(z\mid\text{slice }k)
      \;<\;\sigma_z^2 .
    \tag{I4}
$$

How fast $\sum_k w_k\zeta_k^2\to1$ with $N_s$ is a tracking-free measure of a
rule's quality (Section 5).

## 3. The five Furman prescriptions

Furman *et al.* [1] compare five rules. Attribution as given there: #1 is from
Tennyson's APIARY [7 of Ref. 1]; #3 is the Hirata/Krishnagopal choice; #5 is
what LIFETRAC uses. #2 and #4 are stated without attribution.

### 3.1 Algorithm #1 — equal spacing, pointwise-density weights

Nodes are uniformly spaced and weighted by the density sampled *at the node*:

$$
    \frac{z_k}{\sigma_z}=\frac{2k}{N_s-1}\left(1+\frac{N_s-3}{12}\right),
    \qquad
    w_k=\frac{\hat\rho_\ell(z_k)}{\displaystyle\sum_{m=-L}^{L}\hat\rho_\ell(z_m)} .
$$

Because $2L=N_s-1$, the outermost node sits at

$$
    \frac{z_L}{\sigma_z}=1+\frac{N_s-3}{12},
$$

so the rule carries its own truncation policy: the covered half-span is
$1\sigma_z$ at $N_s=3$, $2\sigma_z$ at $N_s=15$, $3.33\sigma_z$ at $N_s=31$ —
it grows linearly in $N_s$ while the spacing shrinks only like $1/N_s$ times
that same factor. The weights are a *midpoint sample* of the density, not the
integrated charge of a bin, so the two errors — truncation and sampling — do not
cancel. This is the mechanism behind the non-uniform convergence Furman
reports: #1 is the worst of the five at small $N_s$ but becomes competitive
with #4 beyond roughly 50 kicks, once its span has opened up.

### 3.2 Algorithm #2 — equal charge, node at the slice median

Divide the Gaussian into $N_s$ slices of equal area, so

$$
    w_k=\frac{1}{N_s}\quad\text{for all }k .
$$

Let $\lambda_k$ be the inner edge of slice $k>0$ (the central slice occupies
$[-\lambda_1,+\lambda_1]$). Equal charge means the cumulative distribution
advances by $1/N_s$ per slice, so

$$
    \Phi(\lambda_k)=\frac12+\frac{2k-1}{2N_s}
    \;\Longrightarrow\;
    \frac{\lambda_k}{\sigma_z}
      =\sqrt2\,\operatorname{erf}^{-1}\!\left(\frac{2k-1}{N_s}\right),
    \qquad k=1,\dots,L+1,
$$

with $\lambda_{L+1}=\infty$. Algorithm #2 places the node at the point that
**bisects the slice's area** — its median — whose cumulative value is the
midpoint of the slice's cumulative range, $\tfrac12+k/N_s$:

$$
    \boxed{\;\frac{z_k}{\sigma_z}
      =\sqrt2\,\operatorname{erf}^{-1}\!\left(\frac{2k}{N_s}\right),
      \qquad w_k=\frac{1}{N_s}\;}
$$

Note the wording in Ref. [1] calls this the "center of charge", but the formula
is the median. The genuine centre of charge is algorithm #3; the two differ, and
the difference is not negligible ($0.5244$ vs $0.5319$ and $1.2816$ vs $1.3998$
at $N_s=5$).

### 3.3 Algorithm #3 — equal charge, node at the centre of charge

Same edges and same weights $w_k=1/N_s$ as #2, but the node is the conditional
mean. Apply (I3) with $\Phi(\lambda_{k+1})-\Phi(\lambda_k)=1/N_s$:

$$
    \boxed{\;\frac{z_k}{\sigma_z}
      =N_s\big[\varphi(\lambda_k)-\varphi(\lambda_{k+1})\big],
      \qquad w_k=\frac{1}{N_s}\;}
$$

with $\varphi(\lambda_{L+1})=\varphi(\infty)=0$, so the outermost node is
simply $N_s\varphi(\lambda_L)$ and stays finite despite the infinite bin.

Because the Gaussian falls off across each positive-side slice, the conditional
mean always lies **outside** the median, so #3 nodes are systematically farther
from the origin than #2 nodes. #3 preserves the first moment of every slice by
construction; #2 does not. For any kick that is locally linear in $z$, #3 is
exact per slice and #2 is not — which is why #3 should be preferred over #2
whenever both are available at the same cost. They cost the same.

### 3.4 Algorithm #4 — $\sqrt{\rho}$ weights with centre-of-charge nodes

This is Furman's recommended rule. It keeps the centre-of-charge node of #3 but
abandons equal charge, weighting instead by the **square root** of the density:

$$
    w_k=\frac{\sqrt{\hat\rho_\ell(z_k)}}
             {\displaystyle\sum_{m=-L}^{L}\sqrt{\hat\rho_\ell(z_m)}},
    \qquad
    \frac{z_k}{\sigma_z}
      =\frac{1}{w_k}\big[\varphi(\lambda_k)-\varphi(\lambda_{k+1})\big],
$$

where the edges $\lambda_k$ are now defined by the requirement that slice $k$
carry exactly charge $w_k$:

$$
    \Phi(\lambda_1)=\frac12+\frac{w_0}{2},
    \qquad
    \Phi(\lambda_{k+1})=\Phi(\lambda_k)+w_k \quad (k\ge1),
    \qquad \lambda_{L+1}=\infty .
$$

The node formula is (I3) again, now with a slice charge of $w_k$ instead of
$1/N_s$ — algorithm #3 is the special case $w_k\equiv1/N_s$.

The system is coupled: $w_k$ depends on $z_k$ through the density, and $z_k$
depends on $w_k$ through the edges. Solve by fixed-point iteration:

```text
w_k <- 1/Ns                                  # start from equal charge
repeat until converged:
    lambda_1   <- Phi^-1(1/2 + w_0/2)
    lambda_k+1 <- Phi^-1(Phi(lambda_k) + w_k)          k = 1..L-1
    lambda_L+1 <- infinity
    z_0        <- 0
    z_k        <- [phi(lambda_k) - phi(lambda_k+1)] / w_k     k = 1..L
    w_k        <- sqrt(phi(z_k)),  then normalise  w_0 + 2*sum_{k>=1} w_k = 1
```

Plain fixed-point iteration from equal charge converges; no damping or
line search is needed.

**Why $\sqrt{\rho}$?** Equal-charge rules put every node where the charge is,
which under-populates the tails where the source is longitudinally far from the
particle and the drifted transverse size is largest. Weighting by
$\sqrt{\hat\rho}$ is a compromise between "weight $\propto$ charge"
($w\propto\hat\rho$, i.e. #1's rule) and "weight uniform", pushing nodes and
weight outward. Section 5 shows the resulting moment fidelity is the best of the
five at every $N_s$ tested.

### 3.5 Algorithm #5 — minimum cumulative-distribution mismatch

Choose $\{z_k,w_k\}$ to minimise the area enclosed between the two cumulative
distributions,

$$
    A=\int_0^{\infty}\big|\,G(\zeta)-S(\zeta)\,\big|\,\mathrm d\zeta,
    \qquad
    G(\zeta)=\Phi(\zeta)-\tfrac12,
$$

where $S$ is the staircase generated by the delta train,

$$
    S(\zeta)=\int_0^{\zeta}\hat\rho_s
            =\frac{w_0}{2}+\sum_{k\ge1,\;\zeta_k\le\zeta}w_k .
$$

The central delta contributes $w_0/2$ because the integration starts at its
location. Normalization guarantees $S(\infty)=G(\infty)=\tfrac12$, so $A$ is
finite.

$A$ is piecewise analytic, which makes the objective cheap and exact. On an
interval where $S\equiv c$ the integrand is $D(\zeta)=\Phi(\zeta)-\tfrac12-c$,
monotonically increasing with a single zero at $\zeta^\ast=\Phi^{-1}(\tfrac12+c)$,
and

$$
    \int D(\zeta)\,\mathrm d\zeta
      =\zeta\Phi(\zeta)+\varphi(\zeta)-\left(\tfrac12+c\right)\zeta
      \equiv F_c(\zeta),
$$

using $\int\Phi=\zeta\Phi+\varphi$. Split each interval at $\zeta^\ast$ when the
crossing falls inside it and sum $|F_c|$ increments. The final interval
$[\zeta_L,\infty)$ has $c=\tfrac12$, $D=\Phi-1\le0$, and closes analytically:

$$
    \int_{\zeta_L}^{\infty}\big[1-\Phi(\zeta)\big]\mathrm d\zeta
      =\varphi(\zeta_L)-\zeta_L\big[1-\Phi(\zeta_L)\big].
$$

**No optimizer is needed.** Ref. [1] describes #5 as "most easily solved by
iteration" and an optimizer does work, but both stationarity conditions are
closed form. Differentiating with respect to a node, the boundary terms give

$$
    \big|G(\zeta_k)-c_{k-1}\big|=\big|G(\zeta_k)-c_k\big|
    \;\Longrightarrow\;
    \Phi(\zeta_k)=\frac12+\frac{c_{k-1}+c_k}{2},
$$

so **each node sits at the cumulative midpoint of its own jump**. Differentiating
with respect to a weight — which shifts every level below it — gives

$$
    \int_{\zeta_k}^{\zeta_{k+1}}\operatorname{sgn}\!\big(G(\zeta)-c_k\big)\,\mathrm d\zeta=0
    \;\Longrightarrow\;
    \Phi^{-1}\!\left(\tfrac12+c_k\right)=\frac{\zeta_k+\zeta_{k+1}}{2},
$$

so **each level crosses the exact CDF at the arithmetic midpoint of its
interval**. Alternating the two is a pure fixed-point iteration from algorithm
#2, and it reproduces the published values (Section 4) to six digits. The first
condition collapses to #2's node formula when the weights are equal, which
checks both.

Counting: for odd $N_s$ the unknowns are $\zeta_1..\zeta_L$ and $c_0..c_{L-1}$
(with $c_L=\tfrac12$), matched by $L$ node conditions and $L$ level conditions.
For even $N_s$ there is no central node, $c_0=0$ is fixed, the first interval has
no crossing, and the count balances at $2L-1$.

## 4. Reference values and a published erratum

All five rules were re-derived from the formulas above and evaluated at
$N_s=5$ for comparison with Table 1 of Ref. [1]:

| | #1 | #2 | #3 | #4 | #5 |
|---|---|---|---|---|---|
| $z_1/\sigma_z$ | 0.5833333 | 0.5244005 | 0.5319032 | 0.678722 | 0.636233 |
| $z_2/\sigma_z$ | 1.1666667 | 1.2815516 | 1.3998094 | 1.598982 | 1.441560 |
| $w_0$ | 0.2702873 | 0.2 | 0.2 | 0.260561 | 0.249603 |
| $w_1$ | 0.2280002 | 0.2 | 0.2 | 0.232216 | 0.225772 |
| $w_2$ | 0.1368561 | 0.2 | 0.2 | **0.137503** | 0.149426 |

Agreement with the published table is to 5–6 digits for #1, #2, #3, #5 and for
the node positions of #4.

**Erratum.** Table 1 of Ref. [1] prints $w_2=0.17350$ for algorithm #4. That
value makes the weights sum to $1.072$, violating the normalization constraint.
The self-consistent value is $w_2=0.137503$, which sums to exactly $1$ and
reproduces the published $z_2=1.59898$ through the centre-of-charge relation.
Use $0.137503$ when validating an implementation against that table.

## 5. Moment fidelity

By (I4) the delta train always under-represents the second moment. Evaluating
$\sum_k w_k\zeta_k^{2}$ (target $1$) and $\sum_k w_k\zeta_k^{4}/3$ (target $1$)
gives a tracking-free ranking:

| $N_s$ | rule | $\sum w\zeta^2$ | $\sum w\zeta^4/3$ | half-span $/\sigma_z$ |
|---|---|---|---|---|
| 5 | #1 | 0.5277 | 0.1866 | 1.17 |
| 5 | #2 | 0.7669 | 0.3697 | 1.28 |
| 5 | #3 | 0.8970 | 0.5226 | 1.40 |
| 5 | #4 | **0.9171** | **0.6321** | 1.60 |
| 5 | #5 | 0.8038 | 0.4549 | 1.44 |
| 5 | GH | 1.0000 | 1.0000 | 2.86 |
| 15 | #1 | 0.8233 | 0.5502 | 2.00 |
| 15 | #2 | 0.9188 | 0.6780 | 1.83 |
| 15 | #3 | 0.9758 | 0.8079 | 1.94 |
| 15 | #4 | **0.9879** | **0.9149** | 2.38 |
| 15 | GH | 1.0000 | 1.0000 | 6.36 |
| 31 | #1 | 0.9928 | 0.9643 | 3.33 |
| 31 | #2 | 0.9599 | 0.8068 | 2.14 |
| 31 | #3 | 0.9904 | 0.9000 | 2.24 |
| 31 | #4 | **0.9968** | **0.9719** | 2.83 |
| 31 | GH | 1.0000 | 1.0000 | 9.89 |

(GH = Gauss–Hermite, Section 9.1, exact by construction.)

Three things follow.

1. **#4 leads at every $N_s$ tested**, consistent with Furman's tracking-based
   $Q$ metric. It reaches at $N_s=5$ the second-moment fidelity that #2 needs
   $N_s\approx15$ to match.
2. **#2 is the weakest of the equal-charge family.** At $N_s=31$ it is still at
   $0.960$ while #3 — same cost, same weights, only a different node formula —
   is at $0.990$. Preferring the median over the centroid costs roughly a factor
   $2$ in slice count for the same moment error.
3. **Moment fidelity is a proxy, not the answer.** #5 ranks below #3 here but
   is a legitimate rule that optimises a different functional, and Gauss–Hermite
   is perfect on this metric while placing nodes at $9.9\sigma_z$. The ordering
   from moments must be confirmed against a physical observable before it is
   used to choose a production default.

### 5.1 The observed order is 1, and the tails own it

For equal charge with centroid nodes (#3) the deficit *is* the within-slice
variance sum, by (I4). Splitting that sum into the two semi-infinite outer bins
and everything else:

| $N_s$ | total | interior | tails | tail share |
|---|---|---|---|---|
| 5 | 1.03e-1 | 1.56e-2 | 8.75e-2 | 84.9% |
| 15 | 2.42e-2 | 4.23e-3 | 1.99e-2 | 82.5% |
| 65 | 3.83e-3 | 5.93e-4 | 3.24e-3 | 84.5% |
| 251 | 7.61e-4 | 1.02e-4 | 6.59e-4 | 86.6% |

The fitted local order $-\mathrm d\log(\text{err})/\mathrm d\log N_s$ falls from
**1.33 at $N_s=5$ to 1.18 at $N_s=251$**, drifting toward 1 — and the share of
the error carried by two bins out of $N_s$ *grows* with $N_s$.

The mechanism is analytic. An equal-charge bin has width
$h_k\approx1/(N_s\lambda_k)$ where $\lambda$ is the line density, so

$$
    \sum_k w_k\operatorname{Var}_k
      \approx\frac{1}{12N_s^{3}}\sum_k\lambda_k^{-2},
    \qquad
    \sum_k\lambda_k^{-2}\;\to\;N_s\!\int\!\frac{\mathrm dz}{\lambda(z)},
$$

and $\int\mathrm dz/\lambda$ **diverges** for a Gaussian. Equal-charge slicing of
an unbounded, exponentially decaying density is therefore intrinsically first
order: the bins in the tails grow without bound, and no amount of refinement in
the core fixes them.

This localizes the problem and ranks the remedies:

- **#4** pushes nodes and weight outward, shrinking the tail variance. Measured
  order $\approx1.8$ against #3's $1.3$.
- **A finite span that grows with $N_s$** removes the infinite bins outright.
  This is what #1 does implicitly through $1+(N_s-3)/12$, and it is why #1
  overtakes the equal-charge rules at large $N_s$ despite being worst at small.
- **Gauss–Hermite** (Section 9.1) makes the deficit identically zero. It is the
  textbook remedy for a Gaussian-weighted quadrature on an unbounded domain,
  which is precisely the failure mode measured here.

**Was this a proxy or the real thing? Measured: the real thing.** The concern
was that a tail slice collides at large $|s_c|$, where the drifted source is
largest and the field weakest, so $Q$ might down-weight exactly the bins this
metric says dominate. It does not. At EIC weak–strong parameters the $Q$ order
tracks the deficit order for every bin-based rule:

| rule | $Q$ order, e on p | $Q$ order, p on e | deficit order |
|---|---|---|---|
| #2 `:equal_area` | 1.15 | 1.00 | 0.98 |
| #3 `:equal_area_centroid` | 1.29 | 1.28 | 1.23 |
| #4 `:sqrt_density` | 2.06 | 1.92 | 1.87 |
| #5 `:min_cdf_area` | 1.48 | 1.29 | 1.26 |

Node placement is the binding error in the physical metric too. Full study:
[`gaussian_slicing_convergence_2026_07_31.md`](../history/gaussian_slicing_convergence_2026_07_31.md).

## 6. Slicing as an integrator

Section 1 framed slicing as quadrature. The same discretization is also a
splitting integrator, and separating the two views identifies which error is
actually binding.

### 6.1 The telescoped form

Each slice is applied as a conjugation — forward virtual drift to the collision
point, kick, inverse virtual drift:

$$
    \mathcal M_k=\mathcal D_{\rm rev}^{(k)}\,\mathcal K_k\,\mathcal D_{\rm fwd}^{(k)},
    \qquad s_k=\frac{z-z_k}{2}.
$$

The virtual drift is not a pure drift: because its length $S=(z-z_0)/2$ depends
on $z$, the transverse map alone is not symplectic. The canonical transformation
generated by

$$
    F_2=xp_x+yp_y+zp_z+S(z)\frac{p_x^2+p_y^2}{2},
    \qquad S'(z)=\tfrac12
$$

supplies the compensation $p_z\to p_z-\tfrac14(p_x^2+p_y^2)$, which is exactly
the $p_z$ update in the paraxial virtual drift. The chromatic
($H=(p_x^2+p_y^2)/2(1+p_z)$) and exact drifts carry the analogous term.

Composing the whole collision, the $z$-dependent, $p_z$-shifting parts cancel
between adjacent slices and what survives between kicks is an ordinary
fixed-length drift:

$$
    \mathcal M=\underbrace{\mathcal D_{\rm rev}^{(n)}}_{\text{exit}}
      \circ\,\mathcal K_n\,T(\Delta_{n-1})\,\mathcal K_{n-1}\cdots\mathcal K_1\,
      \circ\underbrace{\mathcal D_{\rm fwd}^{(1)}}_{\text{entry}},
    \qquad
    \Delta_k=\frac{z_k-z_{k+1}}{2}.
$$

The inner steps $\Delta_k$ are **particle-independent**; only the entry offset
$s_1=(z-z_1)/2$ moves with the particle, which is physics — a particle at the
head collides earlier — not an integrator inconsistency. Measured residuals for
the three virtual-drift models:

| check | hirata | chromatic | exact |
|---|---|---|---|
| round trip $\mathcal D_{\rm rev}\mathcal D_{\rm fwd}=\mathcal I$ | 0.0 | 1.6e-16 | 9.1e-17 |
| $T$ depends on $(z_a,z_b)$ only via $\Delta$ | 5e-20 | 3.5e-18 | 3.5e-18 |
| $T(\Delta_1)T(\Delta_2)=T(\Delta_1{+}\Delta_2)$, relative | 9e-19 | 5.2e-15 | 3.5e-15 |
| $p_z$ change across $T$ | 0.0 | 1.6e-16 | 1.0e-16 |

So $T$ is an exact one-parameter group to round-off for all three models, and
the collision is a textbook drift–kick splitting bracketed by two fixed
conjugations.

### 6.2 Which error binds

Two error sources coexist:

- **quadrature** — $\sum_k w_k V(s_k)\ne\int V\,\mathrm ds$;
- **splitting** — even with exact quadrature, interleaved drifts and kicks do
  not reproduce the exact flow, the error coming from $[T,V]$, $[T,[T,V]]$, ….

For symmetric slicing ($z_{-k}=-z_k$, $w_{-k}=w_k$) the telescoped sequence
reads identically forwards and backwards. A symmetric composition has only even
powers in its error expansion, so **the splitting contribution is order $\ge2$.**
The measured order of $\approx1.2$ in Section 5.1 is therefore *not* the
splitting — it is the quadrature, localized in the tail bins.

The practical consequence is sharp. **High-order composition (Yoshida,
Forest–Ruth, Blanes–Moan) raises the order of the splitting in the step size and
cannot repair node placement.** Layered on an equal-charge rule it changes
nothing: the tail defect is untouched and the measured order stays near 1.

> **Closed by measurement (2026-07-31).** This was left contingent on whether the
> tail mechanism survived in $Q$. It does — see the table in Section 5.1 — so the
> binding error is quadrature and composition has nothing to fix. Section 6.3 is
> retained as a record of what would be required, and the group-structure result
> in 6.1 stands on its own, but neither is a live work item.

### 6.3 What composition would require

If that measurement ever justifies it, the implementation surface is the node
list $\{z_k,w_k\}$ plus the order of application — but four things change:

1. **Negative weights become mandatory.** By the Sheng–Suzuki theorem any
   splitting of $T+V$ beyond order 2 using only $T$ and $V$ flows must have a
   negative coefficient (Yoshida-4: $\gamma_0=-2^{1/3}/(2-2^{1/3})\approx-1.702$
   against $\gamma_1\approx1.351$, with $2\gamma_1+\gamma_0=1$). Since the
   composition coefficient *is* the kick strength, some slices carry negative
   charge. Negative virtual-drift lengths are harmless here — the drift is
   already a bookkeeping conjugation rather than real propagation.
2. **Weight and charge must be separated.** A slice weight currently serves as
   both the kick coefficient and the physical charge fraction used for
   luminosity. Under composition those are different numbers.
3. **Position stays physical, weight becomes numerical.** Everything derived
   from $z_k$ — crab displacement and angle, the conditional transverse
   covariance, the hourglass $\sigma(s_k)$ — remains correct automatically.
   Only quantities that read $w_k$ as a charge break.
4. **The stepping variable must be declared.** Uniform steps in $s$ put the
   nodes in the equal-spacing family with $w_k=\gamma_i h\lambda(z_k)$; uniform
   steps in cumulative charge $u=\Phi(z_k/\sigma_z)$ put them in the
   equal-charge family with non-uniform drift lengths. Both are valid, the
   coefficients are not transferable between them, and only the first carries a
   density factor that suppresses far-out nodes.

Use the chromatic or exact virtual drift for any such study. The paraxial drift
has no $p_z$ dependence, hence $z'=\partial H/\partial p_z=0$ and no path
lengthening at all — a model error that does not vanish as $N_s\to\infty$, so a
high-order scheme converges faster to the wrong limit.

## 7. How many slices are enough

Ref. [1] defines a convergence metric by pushing a 1000-particle Gaussian test
distribution once through the thick lens and comparing the four transverse
normalized coordinates against an $N_s=\infty$ reference (taken as algorithm #4
with 300 kicks):

$$
    Q=\sum_{n=1}^{4}\sqrt{\big\langle (X_n-X_{n,\infty})^2\big\rangle},
    \qquad
    (X_1,\dots,X_4)=\left(\frac{x}{\sigma_x},\frac{x'}{\sigma_{x'}},
                          \frac{y}{\sigma_y},\frac{y'}{\sigma_{y'}}\right).
$$

The metric deliberately involves no lattice parameter — it judges the
beam–beam element in isolation. Findings: algorithm #4 converges fastest in
every case tried; algorithm #1 does not converge uniformly but becomes
competitive beyond $\sim50$ kicks.

The stopping criterion is a **noise-floor argument**. With radiation damping
time $\tau$ in turns, the equilibrium rms beam size fluctuates by
$\delta\sigma/\sigma\simeq1/\sqrt\tau$, so refining the beam–beam element below

$$
    Q\simeq\frac{4}{\sqrt\tau}
$$

(the factor 4 being the number of terms in $Q$) buys nothing. For PEP-II with
$\tau=5400$ this gives $Q\simeq0.05$, satisfied by all five rules at $N_s=3$.

> **Caveat for hadron rings.** This criterion is derived from radiation-damping
> fluctuations and therefore does **not** transfer to a weakly damped or
> undamped beam. As $\tau\to\infty$ the threshold $4/\sqrt\tau\to0$, so it does
> not merely fail to apply — it demands infinitely many slices and returns no
> usable bound at all.

### 7.1 What to use instead: the model-error yardstick

For an undamped ring, compare the slicing error against an error the run is
**already accepting**. The most useful one is the virtual-drift model, measured
at converged slicing ($N_s=601$, EIC parameters):

| direction | $\lvert$hirata $-$ exact$\rvert$ | $\lvert$chromatic $-$ exact$\rvert$ |
|---|---|---|
| electron on proton | 2.93e-4 | 2.76e-8 |
| proton on electron | 3.88e-5 | 1.41e-9 |

The default `HirataParaxialDrift` therefore contributes $\sim4\times10^{-5}$ to
$Q$ on the hadron side no matter how many slices are used, because it drops the
$\delta$ dependence entirely and so produces no path lengthening (Section 6.3).
`ChromaticDrift` removes that floor for essentially no cost.

**Applied to the EIC hadron beam as the weak beam** (proton tracked, 7 mm
electron strong beam sliced, `:sqrt_density`):

| $N_s$ | 1 | 3 | 4 | 5 | 7 | 9 | 11 | 15 | 21 | 31 | 45 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| $Q$ | 3.8e-4 | 6.7e-5 | 4.1e-5 | 2.8e-5 | 1.5e-5 | 9.8e-6 | 6.8e-6 | 3.8e-6 | 2.1e-6 | 9.9e-7 | 4.9e-7 |

- With the **default paraxial drift**, slicing falls below the drift-model error
  at $N_s=4$. Use $N_s=5$; more slices refine a term that is no longer leading.
- With **chromatic or exact drift**, slicing becomes the leading error and
  $N_s=11$–$15$ gives $Q\approx4$–$7\times10^{-6}$.

Converting $Q$ to a long-term tolerance requires an assumption. Treating the
per-coordinate error $\approx Q/4$ as an independent per-turn kick — an **upper
bound**, since the error is systematic and only resampled by synchrotron motion —
gives a relative emittance growth of order $(Q/4)^2$ per turn:

| | $N_s=5$ | $N_s=9$ | $N_s=15$ | $N_s=31$ | paraxial drift |
|---|---|---|---|---|---|
| growth over $10^9$ turns | 5e-2 | 6e-3 | 9e-4 | 6e-5 | 9e-2 |

The last column is the point: at the default drift setting the drift model alone
consumes more of the budget than any slice count can recover. **Fix the drift
model before adding slices.** These are order-of-magnitude conversions; the
defensible hadron criterion is still a measured long-term emittance-growth rate
or diffusion coefficient, which this single-pass metric cannot supply.

## 8. Even slice counts

Ref. [1] assumes $N_s$ odd. The generalizations are straightforward.

For equal-charge rules (#2, #3) there is no central slice; slice $j=1,\dots,N_s$
spans the cumulative interval $[(j-1)/N_s,\;j/N_s]$ with edges

$$
    \frac{\lambda_j}{\sigma_z}=\Phi^{-1}\!\left(\frac{j}{N_s}\right).
$$

The **median** node (#2) sits at cumulative $(2j-1)/2N_s$:

$$
    \frac{z_j}{\sigma_z}=\Phi^{-1}\!\left(\frac{2j-1}{2N_s}\right)
      =\pm\sqrt2\,\operatorname{erf}^{-1}\!\left(\frac{2i-1}{N_s}\right),
    \qquad i=1,\dots,N_s/2 ,
$$

the right-hand form counting outward from the centre. The **centroid** node (#3)
is (I3) applied to the same edges. Rules #4 and #5 generalize by simply dropping
the $w_0$ term from the normalization and the edge recursion.

## 9. Rules outside Furman's five

### 9.1 Gauss–Hermite quadrature

Since slicing is quadrature against a Gaussian weight (Section 1), the
textbook-optimal choice for *polynomial* integrands is Gauss–Hermite. Using the
probabilists' Hermite polynomials $\mathrm{He}_n$, the $N_s$-point rule places
nodes at the roots of $\mathrm{He}_{N_s}$ with weights that make

$$
    \sum_k w_k\,\zeta_k^{\,m}=\int\zeta^m\varphi(\zeta)\,\mathrm d\zeta
    \qquad\text{exactly for } m\le 2N_s-1 .
$$

Nodes and weights are obtained without root-finding by the Golub–Welsch
construction [5]: form the symmetric tridiagonal Jacobi matrix with zero
diagonal and off-diagonal entries $\sqrt{k}$, $k=1,\dots,N_s-1$; the eigenvalues
are the nodes $\zeta_k$ and the weights are the squared first components of the
normalized eigenvectors. At $N_s=5$:

$$
    \zeta=(0,\;\pm1.355626,\;\pm2.856970),
    \qquad
    w=(0.533333,\;0.222076,\;0.011257).
$$

It is exact on the moment table of Section 5 by construction, and it is the only
rule here that preserves $\sigma_z$ itself.

> **Measured, and it loses.** An earlier version of this section argued from
> Section 5.1 that Gauss–Hermite should win, on the grounds that Gaussian
> quadrature against an unbounded weight is the textbook remedy for exactly the
> tail-limited failure mode measured there. **That argument was wrong.** At EIC
> weak–strong parameters it converges at order $1.0$ in $Q$ and is $11\times$
> worse than $\sqrt\rho$ weighting at $N_s=61$ — better than equal charge with
> median nodes, worse than everything else. See
> [`gaussian_slicing_convergence_2026_07_31.md`](../history/gaussian_slicing_convergence_2026_07_31.md)
> and `validation/gaussian_slicing_convergence.jl`.

The reason the argument failed is the reservation the section already carried,
which turns out to dominate: **the integrand is not polynomial.**
$\mathcal K(z)$ carries the hourglass factor and the drifted covariance, so
Gauss–Hermite's optimality guarantee does not extend to it, and the resolution
it spends on far-out nodes — $2.86\sigma_z$ at $N_s=5$, $9.89\sigma_z$ at
$N_s=31$ — is spent where the physical charge is not. Fixing the *moments* of
the source is not the same as fixing the *kick*, and this is the cleanest
available demonstration of the difference.

Two practical notes for anyone reusing it. The weights underflow to zero beyond
$N_s\approx100$ in Float64 (24 of 101 nodes at $N_s=101$); that is harmless — a
zero weight is a zero kick — but it caps the useful $N_s$. And a far-out node is
not free: it costs a full field evaluation at a plane where the drifted source
is largest and the field weakest.

### 9.2 Xsuite / xfields `TempSlicer`

Xsuite's 6D beam–beam element slices with `xfields.TempSlicer` [4], which offers
three modes. Read against the derivations above they are not new rules:

| Xsuite mode | Weights | Nodes | Equivalent |
|---|---|---|---|
| `unicharge` | $1/N_s$ | centre of charge | **Furman #3** |
| `unibin` | $\propto e^{-z_k^2/2}$ | uniform spacing | **Furman #1** family |
| `shatilov` | $\propto e^{-z_k^2/4}=\sqrt{\hat\rho_\ell(z_k)}$ | centre of charge, iterated | **Furman #4** |

The identification of `shatilov` with algorithm #4 follows from
$e^{-z^2/4}=\sqrt{e^{-z^2/2}}$: it is the $\sqrt{\rho}$ weighting of Section 3.4
with the same centre-of-charge nodes and the same fixed-point iteration.
Furman's rule #4 is therefore the de-facto default in current mainstream
practice, even though Ref. [1] attributes algorithm #5 to LIFETRAC.

Truncation policies differ in detail — `unicharge` starts its edge recursion at
a finite $-5\sigma_z$, and `unibin` uses a span rule that widens with $N_s$
towards $\sim5\sigma_z$ rather than Furman's $1+(N_s-3)/12$. Any claim of
numerical equivalence to Xsuite must be checked against the current source, not
against this table.

### 9.3 Truncation variants

Every practical rule truncates. Two policies are in use and they are not
equivalent:

- **Infinite outer bins**, with the outermost node at the finite centre of
  charge of a semi-infinite slice (#2, #3, #4). All charge is retained.
- **Hard cut at $\pm Z\sigma_z$** with the surviving weights renormalized. Charge
  beyond the cut is discarded and the retained charge is inflated to compensate.
  This is what Octopus `:equal_width` does with $Z=N_s\Delta/2\sigma_z$.

The second is only harmless when the tail charge is negligible against the
target accuracy. It is a separate convergence parameter from $N_s$ and should be
scanned separately.

### 9.4 Observable-matched quadrature

Rules #1–#5 and Gauss–Hermite all approximate the *source*. Nothing forces that
choice: one can instead choose $\{z_k,w_k\}$ to minimise the error in the
*observable*, which is what Furman's $Q$ metric measures but does not optimise.
Algorithm #5 is the closest existing rule in spirit, but it minimises CDF
mismatch, a property of the source alone.

The natural generalization is to minimise $Q$ itself, or a luminosity-weighted
error, over $\{z_k,w_k\}$ for a given $N_s$. The resulting nodes depend on
$\sigma_z/\beta^\ast$, aspect ratio and crossing angle, so this yields a
per-machine table rather than a universal formula — acceptable for a fixed
design point such as EIC, and it would establish the true lower bound against
which #1–#5 and Gauss–Hermite should be scored. This is an extension, not
established practice, and is recorded here as a hypothesis to test.

### 9.5 Empirical slicing of a sampled bunch

All of the above assume an *analytic* Gaussian. When the source is a
macroparticle distribution — strong–strong, or a non-Gaussian source — the
boundaries must come from the sample instead. Octopus does this in
`LongitudinalSlicing` (`src/tasks/strongstrong/`), whose
`method = :normal_quantile` with `center_position = :centroid` is the sampled
analogue of algorithm #3: equal-probability boundaries from the measured mean
and rms, with each node at the empirical centroid of its slice. The empirical
family also admits rules with no analytic counterpart, such as exact
equal-count slicing by sorting.

## 10. What Octopus implements today

`GaussianStrongBeamSpec` (`src/elements/strong_beam.jl`) implements every rule in
this note. All five Furman prescriptions reproduce Table 1 at $N_s=5$ to better
than $5\times10^{-6}$ per entry; Gauss–Hermite is verified against moment
exactness through order $2N_s-1$ (`test/runtests.jl`).

| `slice_method` | Rule | Construction |
|---|---|---|
| `:equal_area` | **#2** | closed form; bit-identical to the pre-existing implementation |
| `:equal_area_centroid` | **#3** | closed form, $N_s[\varphi(\lambda_k)-\varphi(\lambda_{k+1})]$ |
| `:sqrt_density` (default since 2026-07-31; this table once said `:equal_area`) | **#4** | fixed point (Section 3.4) |
| `:min_cdf_area` | **#5** | fixed point (Section 3.5) |
| `:equal_spacing_density` | **#1** | closed form |
| `:gauss_hermite` | — | Golub–Welsch |
| `:equal_width` | #1 *family*, not #1 | uniform nodes, **integrated** bin charge |
| explicit | — | `slice_center` + `slice_weight` bypass `slice_method` |

`:equal_width` remains distinct from `:equal_spacing_density`: its weights are
the exact Gaussian charge of each bin,

$$
    w_i=\frac{\Phi\!\left(\left(i+\tfrac12\right)\Delta\right)
              -\Phi\!\left(\left(i-\tfrac12\right)\Delta\right)}
             {2\Phi\!\left(N_s\Delta/2\right)-1},
    \qquad \Delta=\frac{\texttt{slice\\_width}}{\sigma_z},
$$

against #1's $w_k\propto\varphi(z_k)$; at $N_s=5$ with matched spacing they
differ by $2.0\times10^{-3}$. It also has **two** convergence parameters — a
study that raises $N_s$ at fixed `slice_width` stops converging once the extra
bins fall outside the bunch.

### Measured ranking

At EIC weak–strong parameters, $Q$ against an $N_s=601$ reference (electron on
proton; the reversed direction gives the same ordering with $Q$ about
$600\times$ smaller). The reference's own residual — Richardson extrapolated
from solves at $N_s/2$, $N_s$, $2N_s$, measured order $p=2.05$ — is
$5.3\times10^{-7}$, so every entry below is resolved by $100\times$ or more:

| rule | $N_s=5$ | $N_s=15$ | $N_s=31$ | order |
|---|---|---|---|---|
| **`:sqrt_density`** | **9.50e-3** | **1.01e-3** | **2.28e-4** | **2.06** |
| `:equal_area_centroid` | 1.15e-2 | 1.89e-3 | 6.84e-4 | 1.29 |
| `:gauss_hermite` | 1.49e-2 | 2.57e-3 | 1.23e-3 | 1.00 |
| `:min_cdf_area` | 3.51e-2 | 6.05e-3 | 1.74e-3 | 1.48 |
| `:equal_area` | 4.03e-2 | 1.06e-2 | 4.54e-3 | 1.15 |
| `:equal_spacing_density` | 1.17e-1 | 3.51e-2 | 1.04e-3 | non-uniform |
| `:equal_width` | 1.71e-1 | 4.61e-2 | 6.43e-4 | non-uniform |

`:sqrt_density` is the rule to use: $10.6\times$ more accurate than
`:equal_area` at $N_s=15$ and $20\times$ at $N_s=31$, for identical cost, and it
is also Xsuite's default.

**Correction (2026-08-05_b audit, U26-1).** This paragraph previously read "The
default is still `:equal_area` … `docs/todo.md` records that as an open call",
and the table above marked `:equal_area` as the default. Both were stale:
**`:sqrt_density` has been the shipped default since 2026-07-31**
(`ParamMeta(default=:sqrt_density)` at `src/elements/strong_beam.jl`, and the
`GaussianStrongBeamSpec` constructors), and `docs/todo.md` records the change as
done. The original text is kept here rather than deleted because the
contradiction it created was live: §10 forty lines above already annotated the
change, so the note asserted both, and a reader taking this paragraph at face
value believed production ran the rule this table ranks fifth. Pass
`slice_method = :equal_area` explicitly to reproduce pre-2026-07-31 results.

Reproduce with `validation/gaussian_slicing_convergence.jl`. Full study:
[`gaussian_slicing_convergence_2026_07_31.md`](../history/gaussian_slicing_convergence_2026_07_31.md).

## References

1. M. Furman, A. Zholents, T. Chen and D. Shatilov, "Comparisons of Beam-Beam
   Simulations," PEP-II/AP Note 95.39, LBL-37680, CBP Note-152, August 28, 1995.
   <https://escholarship.org/uc/item/8nd6g4pv>
   (Summarizes the longer CBP Tech Note-59 / PEP-II AP Note 95.04, July 13,
   1995.)

2. K. Hirata, H. Moshammer and F. Ruggiero, "A symplectic beam-beam interaction
   with energy change," *Particle Accelerators* **40** (1993), 205–228.
   <https://research.kek.jp/people/dmzhou/BeamPhysics/SAD/Beam-beam_Hirata-1992.pdf>

3. D. Xu, V. S. Morozov, D. Sagan, Y. Hao and Y. Luo, "Enhanced beam-beam
   modeling to include longitudinal variation during weak-strong simulation,"
   arXiv:2403.03137. <https://arxiv.org/abs/2403.03137>

4. Xsuite collaboration, `xfields.beam_elements.TempSlicer` and the 6D
   beam-beam documentation.
   <https://xsuite.readthedocs.io/en/stable/beambeam.html>

5. G. H. Golub and J. H. Welsch, "Calculation of Gauss quadrature rules,"
   *Mathematics of Computation* **23** (1969), 221–230.

6. M. A. Furman, "Beam-beam simulations with the Gaussian code TRS,"
   LBNL-42669 / CBP Note-272, ICAP'98.
   <https://www.slac.stanford.edu/xorg/icap98/papers/F-Th22.pdf>
