# Gaussian Longitudinal Slicing Rules and their EIC Convergence (2026-07-31)

Record of implementing all five Furman slicing prescriptions plus Gauss-Hermite
quadrature in `GaussianStrongBeamSpec`, and of the convergence study at EIC
weak-strong parameters that both verifies them and ranks them.

Theory: [`../theory/gaussian_longitudinal_slicing.md`](../theory/gaussian_longitudinal_slicing.md).
Measurement: `validation/gaussian_slicing_convergence.jl`.

**Headline, stated up front because two results reverse prior expectations:**

1. **Gauss-Hermite loses.** It is moment-exact by construction, yet it converges
   at order 1.0 in the physical metric and is 11x worse than `:sqrt_density` at
   `ns = 61`. Moment fidelity is the wrong objective for this integrand. An
   earlier draft of the theory note called it "the textbook remedy" for the
   measured failure mode; that was wrong and has been corrected in place.
2. **High-order composition is closed, not deferred.** The tail-limited
   convergence order measured on the tracking-free proxy carries over to the
   physical metric for every bin-based rule. The binding error is quadrature, so
   Yoshida-style composition cannot help. This retires what was item 3a of the
   plan.

## 1. What was asked

Implement Furman's slicing algorithms and Gauss-Hermite quadrature, then run a
convergence study at EIC weak-strong parameters. The two were treated as one
task: a rule that is implemented wrongly does not converge to the same limit as
the others, so the study *is* the verification.

## 2. What was implemented

Six new values for `slice_method` in `src/elements/strong_beam.jl`, alongside
the pre-existing `:equal_area` (Furman #2) and `:equal_width`:

| `slice_method` | Rule | Construction |
|---|---|---|
| `:equal_area_centroid` | Furman #3 | closed form, `ns*(phi(l_k) - phi(l_k+1))` |
| `:sqrt_density` | Furman #4 | fixed point, `w ~ sqrt(rho)` with centroid nodes |
| `:min_cdf_area` | Furman #5 | fixed point (see Section 3) |
| `:equal_spacing_density` | Furman #1 | closed form |
| `:gauss_hermite` | — | Golub-Welsch |

`:equal_area` is unchanged and bit-identical at `ns = 3, 5, 7, 15, 32`.

## 3. Algorithm #5 does not need an optimizer

Ref. [1] describes #5 as a minimisation "most easily solved by iteration", and
the first implementation used Nelder-Mead. Both stationarity conditions turn out
to be closed form. Differentiating the enclosed CDF area with respect to a node
gives

    |G(z_k) - c_{k-1}| = |G(z_k) - c_k|   =>   Phi(z_k) = 1/2 + (c_{k-1} + c_k)/2

— the node sits at the cumulative midpoint of its own jump — and with respect to
a weight gives

    integral over [z_k, z_k+1] of sgn(G - c_k) = 0   =>   Phi^-1(1/2 + c_k) = (z_k + z_k+1)/2

— each level crosses the exact CDF at the arithmetic midpoint of its interval.
Alternating the two is a pure fixed-point iteration that reproduces Table 1 to
six digits and converges for every `ns` tested. The first condition also
collapses to algorithm #2 when the weights are equal, which is a useful
consistency check on both.

## 4. Verification

Table 1 of Ref. [1] at `ns = 5` is reproduced to better than `5e-6` per entry by
all five Furman rules (`test/runtests.jl`, "Gaussian longitudinal slicing
rules", 437 assertions). Gauss-Hermite is verified against moment exactness
instead: an `ns`-point rule reproduces every standard-normal moment through
order `2*ns - 1`.

**Erratum carried into the test.** Table 1 prints `w_2 = 0.17350` for algorithm
#4, which makes that row sum to `1.072` and violate normalization. The
self-consistent value is `0.137503`; it sums to exactly 1 and reproduces the
published `z_2 = 1.59898` through the centre-of-charge relation. The test pins
the corrected value.

## 5. Convergence study

EIC parameters as in `validation/slice_longitudinal_zscan.jl` (275 GeV proton,
10 GeV electron). 4000 test particles, Furman's `Q` (Eq. 10), exact virtual
drift, both collision directions.

**The reference was rebuilt to remove Ref. [1]'s circularity.** Using
"algorithm #4 at 300 kicks" scores every rule against the asymptote of the best
member of its own family. Here the reference is `:sqrt_density` at `ns = 601`,
qualified by its **own** residual via Richardson extrapolation from three solves
at `ns/2`, `ns` and `2*ns`: with error `~ C*ns^-p` the ratio of successive
differences is `2^p`, giving `p` and hence `residual = d_fine / (1 - 2^-p)`.

| direction | measured `p` | reference residual (**floor**) | cross-family `|#3(601)-#4(601)|` |
|---|---|---|---|
| electron on proton | 2.05 | **5.3e-7** | 1.6e-5 |
| proton on electron | 1.95 | **3.4e-9** | 6.6e-8 |

Every `Q` reported below sits 100x or more above its floor.

**Correction (same day).** The first version of this study reported the
cross-family figure as the floor, taking `max()` of the two columns. That
overstates it by roughly 30x: at `ns = 601` the cross-family difference is
dominated by algorithm #3's *own* residual — it converges at order ~1.3 against
the reference's ~2.05, so `2.82e-4 * (601/61)^-1.29 ~ 1.4e-5` accounts for
essentially the whole 1.6e-5 — and says nothing about uncertainty in the
reference. The cross-family number is still printed, for context only. The
Richardson-measured `p` (2.05, 1.95) also agrees with the orders fitted
independently from the `ns` sweep (2.06, 1.92), which is a useful consistency
check on both.

### `Q` versus `ns`, electron (weak) on proton (strong)

Hourglass ratio `sigma_z,strong / beta*_y,weak = 1.071`.

| rule | ns=5 | ns=15 | ns=31 | ns=61 | order |
|---|---|---|---|---|---|
| `:equal_area` (#2) | 4.03e-2 | 1.06e-2 | 4.54e-3 | 2.08e-3 | 1.15 |
| `:equal_area_centroid` (#3) | 1.15e-2 | 1.89e-3 | 6.84e-4 | 2.82e-4 | 1.29 |
| **`:sqrt_density` (#4)** | **9.50e-3** | **1.01e-3** | **2.28e-4** | **5.67e-5** | **2.06** |
| `:min_cdf_area` (#5) | 3.51e-2 | 6.05e-3 | 1.74e-3 | 5.98e-4 | 1.48 |
| `:gauss_hermite` | 1.49e-2 | 2.57e-3 | 1.23e-3 | 6.25e-4 | 1.00 |
| `:equal_spacing_density` (#1) | 1.17e-1 | 3.51e-2 | 1.04e-3 | 1.46e-4 | non-uniform |
| `:equal_width` | 1.71e-1 | 4.61e-2 | 6.43e-4 | 6.86e-4 | non-uniform |

The proton-on-electron direction gives the same ordering and the same orders
with `Q` about 600x smaller throughout, tracking its hourglass ratio of 0.097.

### The tail mechanism carries over

The decisive comparison. `Q` order against the tracking-free second-moment
deficit order, for the bin-based rules:

| rule | `Q` order, e on p | `Q` order, p on e | deficit order |
|---|---|---|---|
| `:equal_area` | 1.15 | 1.00 | 0.98 |
| `:equal_area_centroid` | 1.29 | 1.28 | 1.23 |
| `:sqrt_density` | 2.06 | 1.92 | 1.87 |
| `:min_cdf_area` | 1.48 | 1.29 | 1.26 |

They agree. The concern that `Q` might down-weight the tail bins — a tail slice
collides at large `|s_c|` where the field is weakest — does not materialise.
Node placement is the binding error in the physical metric too.

### Furman's criterion

For the electron ring at `tau = 4000` turns the criterion is `Q ~ 4/sqrt(tau) =
6.3e-2`. Every rule except #1 and `:equal_width` clears it by `ns = 5`,
consistent with Ref. [1]'s finding that PEP-II needed only `Ns = 3`. The
criterion does not apply to the hadron ring, where `Q` is already `~1e-4` at
`ns = 3` but nothing masks the residual.

## 6. What the results changed

**`:sqrt_density` is the rule to use, and it is now the default.** At `ns = 15`
it is 10.6x more accurate than the previous default at identical cost, and 20x at
`ns = 31`. It is also what Xsuite uses by default
(`TempSlicer(mode="shatilov")`). The default was changed from `:equal_area` on
the same day, after the measurement; `test/runtests.jl` pins it so it cannot
drift silently, and `slice_method = :equal_area` reproduces earlier results.

**The hadron-side slice count is set by the drift model, not by the slicing.**
With `:sqrt_density` and the proton as weak beam, `Q` crosses the default
paraxial virtual-drift model error (3.9e-5) at `ns = 4`. Past that, more slices
refine a term that is no longer leading. `ChromaticDrift` removes that floor
(1.4e-9) for essentially no cost, and only then does `ns = 11-15` buy anything.
Recorded in theory note Section 7.1. This makes the drift default, not the slice
count, the open question for hadron studies.

**Gauss-Hermite is not the answer.** It beats `:equal_area` but loses to #3 and
#4 and converges at order 1. The theory note's Section 9.1 previously argued the
opposite from the moment metric alone; it now records the measurement and the
reason the argument failed — the beam-beam integrand carries the hourglass
factor and is not polynomial in `z`, so moment exactness buys nothing, and the
far-out nodes it spends resolution on are where the physical charge is not.

**Composition is closed.** With the tail mechanism confirmed in `Q`, raising the
order of the splitting cannot help; the binding error is quadrature. Item 3a is
retired rather than deferred. The verified virtual-drift group structure
(theory note Section 6.1) stands as a recorded result in case the question
returns for a different reason.

**Still open:** the implicit symplectic integrator as a reference oracle for the
6D longitudinal and energy terms (independent of the above), and
observable-matched nodes.

## 7. Deliberately not done

- `:equal_width` was not renamed, though it is not Furman #1. Its bin weights are
  the integrated charge, not the pointwise density. The distinction is now
  documented in the docstring and both rules exist separately, so a study can
  select the one it means.
- No attempt was made to fix Gauss-Hermite's weight underflow beyond `ns ~ 100`.
  It is harmless (a zero weight contributes a zero kick) and the rule is not
  competitive at any `ns`, so the ceiling costs nothing.
