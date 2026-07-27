# Longitudinal Slice Interpolation of the Beam-Beam Kick

In a sliced strong-strong collision the field of one source slice must be known
at every longitudinal position inside the opposing field slice. Solving Poisson's
equation per particle is unaffordable, so `PICPoissonSolver` (and the spectral and
Gaussian-subtracted solvers built on the same slice loop) solves the field at a
small number of longitudinal *nodes* and interpolates between them.

This note derives what that interpolation costs in accuracy, establishes which
parts of the resulting kick are continuous across a slice boundary and which are
not, and derives the three-node extension (`slice_interpolation = :quadratic`).

Companion notes:
[`beam_beam_longitudinal_kick.md`](beam_beam_longitudinal_kick.md) for the
synchro-beam map this discretizes,
[`weak_strong_6d_model.md`](weak_strong_6d_model.md) for the thin-slice source
model, and [`pic_free_space_kernels.md`](pic_free_space_kernels.md) for the field
solve at each node.

## 1. Geometry and conventions

Write $c$ for the longitudinal coordinate of the source slice plane (its
`center`, either the particle centroid or the bin midpoint — see Section 8) and
$z$ for the longitudinal coordinate of a field particle. The beams
counter-propagate, so the pair meets after each has drifted half their
separation. The implementation drifts the field particle by

$$
    S(z) = \tfrac12\,(z-c),
$$

and the source slice by the opposite amount. It is convenient to name the
**source drift parameter**

$$
    \sigma(z) \;=\; -S(z) \;=\; \tfrac12\,(c-z),
    \qquad
    \frac{d\sigma}{dz} = -\tfrac12 .
$$

Let $\phi(\mathbf r_\perp;\sigma)$ be the mesh potential of the source slice
after it has been drifted by $\sigma$, and
$\mathbf E = -\nabla_\perp\phi$ the corresponding field, in the
$G_{\text{PIC}}=-\ln r$ normalization of
[`pic_free_space_kernels.md`](pic_free_space_kernels.md), so that the kick is
$\Delta\mathbf p_\perp = 2k_{bb}\mathbf E$.

The exact sliced map applies

$$
    \Delta\mathbf p_\perp(z)
      = 2k_{bb}\,\mathbf E\big(\mathbf r_\perp(z);\,\sigma(z)\big),
    \qquad
    \Delta p_z(z)
      = -2k_{bb}\,\frac{\partial\phi}{\partial z}\big(\mathbf r_\perp(z);\sigma(z)\big).
$$

Two things vary with $z$ here, and the distinction is the key to everything
below:

1. the **evaluation point** $\mathbf r_\perp(z)$, the particle's own drifted
   transverse position; and
2. the **field map** itself, through the source drift $\sigma(z)$.

The implementation treats these differently. The evaluation point is computed
exactly per particle (`pic_cpu.jl:242-244`). Only the field map is interpolated.
That is a deliberate and important choice: the entire drift dependence, which is
large and particle-specific, is exact, and the interpolation error is confined to
the much weaker dependence of the *source field* on its own drift.

## 2. The two-node scheme as implemented

For a field slice spanning $[z_L, z_R]$ with width $\Delta = z_R - z_L$
(`param_field.lb`, `param_field.rb`), the solver performs two field solves, at
source drifts

$$
    \sigma_L = \tfrac12(c - z_L),
    \qquad
    \sigma_R = \tfrac12(c - z_R),
    \qquad
    \sigma_L - \sigma_R = \tfrac{\Delta}{2}.
$$

With the normalized slice coordinate

$$
    t = \frac{z - z_L}{\Delta}\in[0,1],
$$

`_slice_interpolation_parameters` returns $h_z^{-1}=1/\Delta$ and
$z_{\text{bias}}=z_R/\Delta$, so that the code's blend weights are
$\texttt{zL} = 1-t$ and $\texttt{zR} = t$. The applied transverse kick is

$$
\boxed{\;
    \Delta\mathbf p_\perp(z)
      = 2k_{bb}\Big[(1-t)\,\mathbf E\big(\mathbf r_\perp(z);\sigma_L\big)
                   + t\,\mathbf E\big(\mathbf r_\perp(z);\sigma_R\big)\Big].
\;}
$$

Since $\sigma$ is affine in $z$, this is ordinary linear interpolation of
$\mathbf E$ in the drift variable over an interval of length
$\Delta\sigma = \Delta/2$.

## 3. Transverse error, and why the transverse kick is continuous

### 3.1 Within a slice

Linear interpolation of a smooth function over $[\sigma_R,\sigma_L]$ gives

$$
    \mathbf E_{\text{interp}} - \mathbf E_{\text{exact}}
      = \tfrac12(\sigma-\sigma_L)(\sigma-\sigma_R)\,
        \frac{\partial^2\mathbf E}{\partial\sigma^2}
      = \frac{\Delta\sigma^2}{2}\,t(t-1)\,
        \frac{\partial^2\mathbf E}{\partial\sigma^2},
$$

which vanishes at both nodes and peaks at mid-slice:

$$
\boxed{\;
    \max_{z}\big|\mathbf E_{\text{interp}}-\mathbf E_{\text{exact}}\big|
      = \frac{\Delta\sigma^2}{8}\left|\frac{\partial^2\mathbf E}{\partial\sigma^2}\right|
      = \frac{\Delta^2}{32}\left|\frac{\partial^2\mathbf E}{\partial\sigma^2}\right|.
\;}
$$

The error envelope is therefore a **scallop**: one-signed within each slice, zero
at both ends.

### 3.2 Across a slice boundary

Slices share boundaries — `param = (lb=boundary[i], center=center[i],
rb=boundary[i+1])` at `pic_cpu.jl:54-57` — so for adjacent field slices $s$ and
$s+1$,

$$
    z_R^{(s)} = z_L^{(s+1)}
    \quad\Longrightarrow\quad
    \sigma_R^{(s)} = \sigma_L^{(s+1)} .
$$

The right node of one slice and the left node of the next are **the same source
drift, hence the same physical source configuration**. Taking limits from either
side of the shared boundary $z^*$,

$$
    \lim_{z\to z^{*-}}\Delta\mathbf p_\perp
      = 2k_{bb}\mathbf E\big(\mathbf r_\perp(z^*);\sigma_R^{(s)}\big)
      = 2k_{bb}\mathbf E\big(\mathbf r_\perp(z^*);\sigma_L^{(s+1)}\big)
      = \lim_{z\to z^{*+}}\Delta\mathbf p_\perp .
$$

**The transverse kick is $C^0$ in $z$ across slice boundaries, exactly, by
construction.** It is not $C^1$: the interpolation slope
$[\mathbf E(\sigma_R)-\mathbf E(\sigma_L)]/\Delta$ generally differs between
adjacent slices, so the kick is continuous piecewise-linear with a kink at every
boundary.

This is a real property of the scheme and worth stating plainly, because it is
the reassuring half of the answer: a particle executing synchrotron motion and
migrating between slices sees a **Lipschitz**, not impulsive, transverse kick.
What it does see is a periodic scalloped modulation of amplitude
$O(\Delta^2)$ sampled at the synchrotron frequency. That is a coherent driving
term, not noise, and it is the mechanism that three nodes attacks.

## 4. The longitudinal kick is *not* continuous

The longitudinal kick is built differently. At `pic_cpu.jl:938`,

```julia
Kz += w * (phiL[ii, jj] - phiR[ii, jj])
```

carries **no** $t$ weighting; the applied kick is
$\Delta p_z = 2k_{bb}(\phi_L-\phi_R)/\Delta$.

To see what that approximates, define $g(z) = \phi(\mathbf r_\perp;\sigma(z))$.
Because $\sigma_L-\sigma_R = \Delta/2$ and $d\sigma/dz=-1/2$,

$$
    \frac{\phi_L-\phi_R}{\Delta}
      = -\frac{g(z_R)-g(z_L)}{\Delta}
      = -g'(\zeta)
    \quad\text{for some }\zeta\in(z_L,z_R),
$$

by the mean value theorem, with $\zeta = m + O(\Delta^2)$ where $m$ is the slice
**midpoint**. So the implemented longitudinal kick is

$$
    \Delta p_z = -2k_{bb}\,g'(m) + O(\Delta^2),
$$

a single secant slope, **constant across the slice**, that is accurate at
mid-slice and drifts away from the truth linearly toward both edges:

$$
\boxed{\;
    \Delta p_z^{\text{impl}}(z) - \Delta p_z^{\text{exact}}(z)
      = -2k_{bb}\,g''(m)\,(z-m) + O(\Delta^2).
\;}
$$

At the shared boundary $z^*$ between slices of width $\Delta_s$ and
$\Delta_{s+1}$, the two secants are centered at different midpoints, so they do
not agree:

$$
\boxed{\;
    \big[\Delta p_z\big]_{z^{*-}}^{z^{*+}}
      = -2k_{bb}\,g''(z^*)\,\big(m_{s+1}-m_s\big)
      = -2k_{bb}\,g''(z^*)\,\frac{\Delta_s+\Delta_{s+1}}{2}
      = O(\Delta).
\;}
$$

For uniform slices the within-slice deviation is a sawtooth of peak amplitude
$k_{bb}|g''|\Delta$ and the boundary jump is exactly twice that,
$2k_{bb}|g''|\Delta$ — a pure sawtooth in $z$ with a genuine step at every
boundary.

**This is the sharp answer to the smoothness question.** The transverse kick is
continuous; the longitudinal kick is discontinuous at first order in the slice
width. It is discontinuous by construction, in exact arithmetic, independent of
grid or particle count. And it lives in the plane that synchrotron oscillation
sweeps, which is exactly where a discontinuity converts into artificial
longitudinal diffusion and, through the beam-beam coupling, transverse emittance
growth.

This is inherited from the standard Hirata-style synchro-beam map rather than
introduced here, but it is the weakest link in the current scheme.

## 5. Continuity breakers below the algorithm

The exact $C^0$ transverse cancellation of Section 3.2 assumes that the field
solve at a given source drift returns the same numbers regardless of which field
slice requested it. Three implementation choices break that assumption. They are
independent of the interpolation order and are **not** fixed by adding nodes.

1. **Per-slice-pair grid sizing.** `_pic_interaction_grids` (`pic_cpu.jl:315`)
   sizes the mesh from the bounding box of the *requesting slice's* particles, so
   adjacent field slices receive different origins $(x_0,y_0)$ and different cell
   sizes $(h_x,h_y)$. The PIC discretization error is a function of those, and it
   does not cancel at the shared boundary. The resulting transverse jump is of
   order the PIC field error itself — plausibly the largest single continuity
   violation in the scheme, and larger than the $O(\Delta^2)$ interpolation error
   it sits beside.

2. **Per-turn re-slicing.** `longitudinal_slices` is called from the instantaneous
   distribution on every collision (`pic_cpu.jl:42-43`). Under the default
   `:equal_area` method the internal boundaries carry histogram shot noise, and
   the outermost boundaries are pinned to $\min z$ and $\max z$ — i.e. to single
   extreme macroparticles. Node positions therefore jitter turn to turn, which
   converts a deterministic $O(\Delta^2)$ interpolation error into a *fluctuating*
   one. That is a diffusion source rather than a coherent driving term, and it is
   the mechanism most likely to be mistaken for physical emittance growth.

3. **Source evolution between collisions.** Slice pairs are processed in collision
   -time order (`_slice_collision_order`), and each interaction writes its result
   back (`_pic_store_slice!`) before the next reads it (`_pic_extract_slice`). The
   source slice state when it serves as the right node of field slice $s$ is
   therefore not the state when it serves as the left node of slice $s+1$: the
   intervening collisions have kicked it. This breaks the Section 3.2
   cancellation by $O(1/N_{\text{slices}})$ of the total beam-beam kick, which is
   not small.

Ranking these against the interpolation error is an empirical question, which is
what `validation/slice_longitudinal_zscan.jl` exists to answer.

## 6. Two distinct $O(\Delta^2)$ longitudinal errors

It is essential not to conflate them:

- **Interpolation error** — representing $\mathbf E(\sigma)$ between two solved
  nodes by a straight line. Scales as $\Delta^2\partial_\sigma^2\mathbf E$.
  *Removed by adding nodes.*
- **Slicing error** — representing the continuous line density $\rho(z)$ by $N$
  thin planes carrying the bin populations at the bin centroids. Also scales as
  $\Delta^2$, by the midpoint-rule remainder. *Not touched by adding nodes*;
  it requires more slices, or a higher-order longitudinal quadrature.

Both are $O(\Delta^2)$ and both shrink as $N^{-2}$, so a convergence study in $N$
alone **cannot separate them**. If the slicing error dominates, three nodes buys
nothing measurable. The z-scan of Section 9 separates them by construction,
because it compares against a per-particle exact solve *of the same sliced source*
— holding the slicing error fixed and exposing only the interpolation error.

## 7. The three-node extension

### 7.1 Weights

Add a third solve at the slice **midpoint** $z_M = (z_L+z_R)/2$, i.e. at source
drift $\sigma_M = \tfrac12(c - z_M)$. The quadratic Lagrange basis on the
equispaced nodes $t\in\{0,\tfrac12,1\}$ is

$$
    L_L(t) = 2\big(t-\tfrac12\big)(t-1) = 2t^2-3t+1,
    \qquad
    L_M(t) = -4t(t-1),
    \qquad
    L_R(t) = 2t\big(t-\tfrac12\big),
$$

with $L_L+L_M+L_R \equiv 1$, giving

$$
\boxed{\;
    \Delta\mathbf p_\perp(z)
      = 2k_{bb}\Big[L_L(t)\,\mathbf E(\sigma_L)
                   + L_M(t)\,\mathbf E(\sigma_M)
                   + L_R(t)\,\mathbf E(\sigma_R)\Big].
\;}
$$

At $t=0$ and $t=1$ the weights collapse to $(1,0,0)$ and $(0,0,1)$, so the
endpoint nodes are still the only contributors at the slice boundaries and **the
$C^0$ property of Section 3.2 is preserved exactly**.

### 7.2 Longitudinal kick

Differentiating the same quadratic gives a longitudinal kick that is *linear*
in $z$ instead of constant:

$$
\boxed{\;
    \Delta p_z(z)
      = -\frac{2k_{bb}}{\Delta}
        \Big[(4t-3)\,\phi_L + (4-8t)\,\phi_M + (4t-1)\,\phi_R\Big].
\;}
$$

Two properties must be checked, and both hold:

- The weights sum to zero, $(4t-3)+(4-8t)+(4t-1)=0$, so a uniform additive offset
  in $\phi$ cancels exactly. This is required — the mesh potential carries an
  arbitrary constant, and the existing two-node formula relies on the same
  cancellation (`pic_cpu.jl:732`).
- At $t=\tfrac12$ the weights are $(-1,0,+1)/\Delta$, reproducing
  $2k_{bb}(\phi_L-\phi_R)/\Delta$ exactly. **The current scheme is precisely the
  three-node formula frozen at mid-slice**, which independently confirms the
  secant analysis of Section 4.

### 7.3 Error and boundary jump

For the transverse kick, quadratic interpolation over $[\sigma_R,\sigma_L]$ with
node spacing $h=\Delta\sigma/2=\Delta/4$ has
$\max|(\sigma-\sigma_0)(\sigma-\sigma_1)(\sigma-\sigma_2)| = 2h^3/3\sqrt3$, hence

$$
\boxed{\;
    \max_z\big|\mathbf E_{\text{interp}}-\mathbf E_{\text{exact}}\big|
      = \frac{h^3}{9\sqrt3}\left|\frac{\partial^3\mathbf E}{\partial\sigma^3}\right|
      \approx \frac{\Delta^3}{998}\left|\frac{\partial^3\mathbf E}{\partial\sigma^3}\right|,
\;}
$$

against $\Delta^2|\partial_\sigma^2\mathbf E|/32$ for two nodes: one full order in
$\Delta$, with a favourable constant.

For the longitudinal kick, differentiating a quadratic interpolant has nodal
error $g'-q' = \tfrac16 g'''\prod_{j\neq i}(z_i-z_j)$, giving $+h^2g'''/3$ at both
endpoints and $-h^2g'''/6$ at the midpoint, so the within-slice error falls from
$O(\Delta)$ to

$$
    \big|\Delta p_z^{\text{impl}} - \Delta p_z^{\text{exact}}\big|
      \le \frac{2k_{bb}\,\Delta^2}{12}\,|g'''| .
$$

The boundary jump improves by more than one order. Both one-sided limits pick up
the *endpoint* error $+h^2g'''/3$ with the **same sign**, so the leading term
cancels in the difference and only the variation of $g'''$ across a slice
survives:

$$
\boxed{\;
    \big[\Delta p_z\big]_{z^{*-}}^{z^{*+}}
      = \frac{h^2}{3}\big(g'''_s - g'''_{s+1}\big) + \dots
      = O(\Delta^3)\,g'''' ,
\;}
$$

against $O(\Delta)$ for two nodes. This is the principal reason to prefer the
three-node scheme: it converts the longitudinal kick from a discontinuous
sawtooth into a nearly continuous piecewise-linear function.

### 7.4 Overshoot caveat

The quadratic weights are not all non-negative on $[0,1]$:
$L_L(t)=(2t-1)(t-1)$ reaches $-1/8$ at $t=3/4$, and $L_R$ likewise at $t=1/4$, so
$\sum|L_i|$ peaks at $1.25$. Quadratic interpolation is not monotonicity
preserving and can overshoot by up to $12.5\%$ of the node spread where
$\mathbf E(\sigma)$ is strongly curved. This is harmless in the core, where the
field is smooth in $\sigma$, but it is a real caveat in the tail slices, whose
nodes are pinned to extreme macroparticles (Section 5, item 2).

### 7.5 Cost

One additional charge deposition, forward FFT, kernel multiply, inverse FFT and
gradient per slice pair per direction. The Green FFT is cached per slice pair
(`green_cache=:slice_pair`) and is reused by the third plane, so the marginal
cost is confined to the solve itself: about $+50\%$ of the field-solve stage,
one extra `_PICFieldWorkspace`, and $+50\%$ of the memory traffic in the particle
loop.

Measured CPU turn time (8 threads, `:normal_quantile` slicing):

| particles/beam | slices | grid | `:linear` | `:quadratic` | ratio |
|---|---|---|---|---|---|
| 100k | 7  | 64  | 1.118 s | 1.131 s | 1.01 |
| 100k | 15 | 64  | 2.979 s | 3.208 s | 1.08 |
| 100k | 15 | 128 | 6.948 s | 7.933 s | 1.14 |
| 1M   | 15 | 128 | 24.483 s | 25.758 s | **1.05** |

The field-solve stage grows by half, but it is not the dominant CPU cost at
production particle counts — deposition and the particle kick loop are — so the
turn-time penalty falls as the particle count rises. At the production point
(1M/beam, 15 slices, grid 128) it is **+5%**.

CUDA is a different story, and the reason is structural rather than arithmetic.
The wavefront and batched-FFT routes pack exactly two field planes per slice-pair
direction (`nplanes = 4 * npairs`, with `÷2` and `÷4` plane-index arithmetic
throughout the deposit, solve and luminosity kernels), so they cannot carry a
third plane without a reindexing of all three routes. `:quadratic` is therefore
implemented only on the CUDA *sequential, non-batched-FFT* route
(`batch_mode = :sequential`, `cuda_async = false`). Measured at 1M/beam,
15 slices, grid 128:

| CUDA route | s/turn | vs production |
|---|---|---|
| wavefront `:linear` (production default) | 0.3201 | 1.00x |
| sequential non-async `:linear` | 0.7940 | 2.48x |
| sequential non-async `:quadratic` | 0.9190 | **2.87x** |

The third plane costs only 1.14x *on its own route*, but that route is itself
2.48x the production default, so the honest cost of `:quadratic` on CUDA today is
**2.87x**, not 1.14x. A CUDA user wanting three-node interpolation should either
run the CPU path (+5%) or wait for wavefront support. CPU/CUDA parity on the
supported route is 7.5e-16 relative.

Compare against the alternative of reducing $\Delta$ by increasing $N$: slice
pairs scale as $N^2$, so halving $\Delta$ costs $4\times$. **Three nodes is
roughly an order of magnitude cheaper than more slices for the same
interpolation-error reduction** — while, per Section 6, doing nothing at all for
the slicing error that more slices would also fix.

## 8. Node placement

Three candidate placements for a third node, and why the midpoint wins.

**Midpoint (adopted).** For three points the Chebyshev-Gauss-Lobatto set on
$[z_L,z_R]$ *is* the equispaced set, so the midpoint is simultaneously the
minimax-optimal interior node and the simplest to compute. It preserves endpoint
sharing, hence $C^0$.

**Slice centroid (rejected).** The centroid is the correct first-moment position
for the *source plane* — it is what makes the thin-slice model reproduce the
bunch's longitudinal moments, and it is why `center_position = :centroid` is the
default (`interface.jl:487`). It is the wrong choice for an *interpolation node*.
Under `:equal_area` slicing the centroid sits off-center, badly so in the tail
slices, which clusters the nodes and degrades the worst-case error on the far
side of the interval. The two roles are distinct and should not be forced to
share a value.

For reference, `center_position` is validated at `interface.jl:494` and consumed
at `slicing.jl:337-344`: `:centroid` takes the mean $z$ of the bin's particles
(falling back to the bin midpoint when the bin is empty), `:midpoint` takes
$(b_s+b_{s+1})/2$. Because `:equal_area` pins $b_1=\min z$ and $b_{N+1}=\max z$,
`:midpoint` places the outer planes halfway to the most extreme macroparticle —
both biased and shot-noise sensitive. It is a systematic-error probe, not a
production setting. Note also that `center` feeds `_slice_collision_order`, so
changing it also perturbs the collision schedule.

**Chebyshev nodes with two solves (rejected).** Keeping two solves but moving them
inward to $m \pm \Delta/(2\sqrt2)$ minimizes the linear-interpolation maximum
error, buying a free factor of $2$ at zero extra cost: with nodes at $\pm c$ on
$[-1,1]$, $\max|(x-c)(x+c)| = \max(1-c^2,c^2)$ is minimized at $c=1/\sqrt2$,
giving $1/2$ against $1$ for endpoints.

This is the wrong trade here. It destroys the shared-endpoint cancellation of
Section 3.2 and converts the currently continuous transverse kick into one with a
step at every slice boundary, in a code whose failure mode of concern is
artificial emittance growth. Endpoint-preserving three-node interpolation gets
both accuracy *and* continuity; Chebyshev two-node trades the wrong one away.

## 9. Expected limits, and how to measure

Two reasons the asymptotic gain of Section 7.3 will not be realized in full.

1. **The CIC floor.** Deposition and interpolation are second order, and the
   CIC-deposited charge is only $C^0$ in the source drift $\sigma$ — a
   macroparticle crossing a cell boundary as the source drifts produces a kink.
   A third $\sigma$-derivative sampled through CIC is therefore noisier than the
   clean estimate suggests. The precedent is `field_derivative = :fourth`
   (`interface.jl:768-775`, and Section 2 of
   [`pic_free_space_kernels.md`](pic_free_space_kernels.md)), which delivered
   $\sim1.6\times$ rather than the $4\times$ its order implies, for exactly this
   reason. `deposit_method = :TSC` is $C^1$ and should show a larger gain than
   `:CIC`; that is a testable prediction of this note.

2. **Shot noise.** Each node's solve carries an $O(N_{\text{slice}}^{-1/2})$
   statistical error. The three-node weights amplify it slightly relative to two
   ($\|L\|_2$ peaks at $0.85$ against $0.79$ at $t=1/4$), which is negligible —
   and in any case the nodes are highly correlated, being the same macroparticles
   at different drifts.

The decisive measurement is a **frozen z-scan**, implemented in
`validation/slice_longitudinal_zscan.jl`: freeze one turn's slicing and one source
state, hold a test particle's $(x,y,p_x,p_y)$ fixed, sweep $z$ finely across
several slice boundaries, and compare $\Delta p_x$, $\Delta p_y$ and $\Delta p_z$
against a per-particle exact reference — the source drifted to that particle's own
$\sigma(z)$, on the *same* grid with the *same* deposition, so that the transverse
PIC error cancels and only the longitudinal interpolation error remains.

For a flat beam $\Delta p_y$ is the observable that matters: the vertical field
varies on the scale $\sigma_y \ll \sigma_x$, so $\partial^2_\sigma E_y$ is larger
than $\partial^2_\sigma E_x$ by roughly the aspect ratio, and the vertical
emittance is the quantity a spurious modulation degrades first.

That single scan separates all four effects at once: the within-slice scallop
(Section 3.1), the slope kink at boundaries (Section 3.2), the transverse jump
from per-slice grid resizing (Section 5, item 1), and the sawtooth step in
$\Delta p_z$ (Section 4).

## 10. Measured

### 10.1 Baseline: `:CIC`, per-slice-pair grid

First run, 2026-07-25. Flat EIC-like pair, $200\,000$ macroparticles per beam,
`grid=(64,64)`, `:CIC`, `:integrated`, 7 normal-quantile slices, 3 slices swept
at 61 samples each; source slice 4 is the bunch centre and slice 6 is off-centre.
Errors are maxima over the scan against the per-particle exact reference.

| source slice | component | peak exact | max err `:linear` | max err `:quadratic` | gain |
|---|---|---|---|---|---|
| 4 | $\Delta p_x$ | $1.7\times10^{-5}$ | $7.5\times10^{-11}$ | $4.4\times10^{-11}$ | 1.7 |
| 4 | $\Delta p_y$ | $1.0\times10^{-5}$ | $2.3\times10^{-9}$ | $3.2\times10^{-10}$ | 7.3 |
| 4 | $\Delta p_z$ | $3.9\times10^{-11}$ | $1.29\times10^{-11}$ | $2.5\times10^{-12}$ | 5.2 |
| 6 | $\Delta p_x$ | $1.7\times10^{-5}$ | $2.2\times10^{-10}$ | $4.0\times10^{-11}$ | 5.5 |
| 6 | $\Delta p_y$ | $8.5\times10^{-6}$ | $1.2\times10^{-9}$ | $5.0\times10^{-10}$ | 2.4 |
| 6 | $\Delta p_z$ | $4.4\times10^{-10}$ | $1.24\times10^{-11}$ | $2.4\times10^{-12}$ | 5.2 |

Slice-boundary discontinuities, normalized by the peak exact kick:

| grid mode | scheme | $\Delta p_x$ | $\Delta p_y$ | $\Delta p_z$ |
|---|---|---|---|---|
| common | `:linear` | $\sim2\times10^{-9}$ | $\sim2\times10^{-8}$ | $0.45-0.52$ |
| common | `:quadratic` | $\sim2\times10^{-9}$ | $\sim2\times10^{-8}$ | $0.039-0.11$ |
| per-slice | `:linear` | $1.0-1.6\times10^{-3}$ | $0.3-4.8\times10^{-3}$ | $0.04-0.69$ |

Four conclusions, and they are not the ones a first guess would give.

1. **Section 3.2 is confirmed to roundoff.** On a common grid the transverse
   boundary jump is $\sim10^{-8}$ relative — floating-point noise. The shared-node
   cancellation is exact, as derived.

2. **The longitudinal sawtooth is enormous.** With `:linear` the $\Delta p_z$ step
   at a slice boundary is **45-52% of the peak longitudinal kick** for the central
   source slice, and the within-slice error reaches 33% of peak. This is by far
   the largest error in the scheme. `:quadratic` cuts the jump by $4-12\times$ and
   the within-slice error by $5.2\times$. The absolute $\Delta p_z$ error is
   $\approx1.2\times10^{-11}$ for both source slices and falls to
   $\approx2.4\times10^{-12}$ — the improvement factor is stable at $5.2$
   independent of where the source slice sits, which is the robust statement; the
   relative figures vary only because the peak kick does.

3. **Transversely, interpolation is not the bottleneck — the grid is.** The
   `:linear` transverse interpolation error is already $\sim10^{-4}$ relative, but
   the per-slice grid resizing of Section 5 item 1 produces a boundary jump of
   $\sim10^{-3}$ relative — roughly $5\times$ larger in absolute terms than the
   interpolation error it sits beside, and it is *unaffected* by adding nodes.
   Anyone chasing transverse smoothness should fix the grid, not the interpolant.

4. **$\Delta p_y$ gains more than $\Delta p_x$ at the bunch centre** (7.3 against
   1.7), as the flat-beam argument predicts: $E_y$ varies on the scale $\sigma_y$,
   so its curvature in $\sigma$ is the larger one. The ordering is not uniform
   across source slices, because the two components' third derivatives do not peak
   at the same drift.

### 10.2 The grid jump is removable — `interaction_grid = :source_slice`

Conclusion 3 above identified per-slice-pair mesh sizing as the dominant
transverse continuity breaker. Sizing one mesh per (source slice, direction) from
the union over all its field slices removes it outright. Re-running the same scan
with the production helper `_pic_union_bounds` that backs
`interaction_grid = :source_slice`:

| grid mode | jump $\Delta p_x$ | jump $\Delta p_y$ |
|---|---|---|
| per-slice-pair (default) | $1.0-1.6\times10^{-3}$ | $0.3-4.8\times10^{-3}$ |
| shared per source slice | $2.4\times10^{-9}$ | $1.9-3.0\times10^{-8}$ |
| common grid (ideal) | $2.1\times10^{-9}$ | $1.6-2.9\times10^{-8}$ |

The shared mesh reaches the ideal common-grid floor exactly — a $5$–$6$ order of
magnitude reduction. The price is resolution, since one mesh must cover the union:

| source slice | $h_x$ ratio | $h_y$ ratio |
|---|---|---|
| 4 | 1.23 | 1.11 |
| 6 | 1.36 | 1.23 |

Cells coarsen by $11-36\%$, so the *smooth* part of the PIC field error rises by
roughly $h^2$, i.e. $20-85\%$. In field-error terms that is a genuine trade: a
smooth $O(h^2)$ error is exchanged for the removal of a $10^{-3}$ discontinuity.

In every other respect it is a strict win. Sharing the mesh collapses the number
of distinct grids, and therefore the slice-pair Green cache:

| mode | cache entries | hits | misses | rebuilds | hit rate |
|---|---|---|---|---|---|
| `:slice_pair` | 450 | 1231 | 450 | 119 | 0.684 |
| `:source_slice` | **30** | 1750 | 30 | 20 | **0.972** |

at 15 slices — a $15\times$ reduction in entries and a fall from 569 Green FFT
builds per 4 turns to 50. The measured CPU turn time is consequently *lower*:

| particles/beam | slices | grid | `:slice_pair` | `:source_slice` | ratio |
|---|---|---|---|---|---|
| 100k | 15 | 64  | 3.190 s | 1.937 s | **0.61** |
| 1M   | 15 | 128 | 25.960 s | 23.337 s | **0.90** |

So `:source_slice` removes the dominant transverse discontinuity *and* runs
10-39% faster. Whether the coarser mesh costs more than the discontinuity gains
is a dynamics question, answered in Section 11 (it does not: growth falls).

**The coarsening figures above are one-directional and understate the cost.**
The shared mesh must cover the source slice drifted across the field beam's
*entire* longitudinal range, and a drifted slice grows as
$\sigma\sqrt{1+(s/\beta^*)^2}$. The drift span is set by the **field** beam's
bunch length while the blow-up is evaluated on the **source** beam's optics, so
the governing ratio is $\sigma_{z,\text{field}}/\beta^*_{\text{source}}$ — and a
collider runs both directions every turn. Measured at 15 slices for the real EIC
pair (electron $\sigma_z=7$ mm, $\beta^*_y=56$ mm; proton $\sigma_z=60$ mm,
$\beta^*_y=72$ mm):

| direction | ratio | source slice | $h_x$ | $h_y$ |
|---|---|---|---|---|
| proton → electron | 0.10 | centre | 1.28 | 1.26 |
| proton → electron | 0.10 | tail | 1.27 | 1.32 |
| **electron → proton** | **1.07** | centre | 1.06 | **2.70** |
| **electron → proton** | **1.07** | tail | 1.10 | **2.69** |

The earlier table in this section covered only the first direction. In the second
the vertical cells are **2.7x coarser**, i.e. roughly $7\times$ worse $O(h^2)$
field error, and that is the production EIC case rather than a contrived one.

A synthetic sweep of the ratio confirms the scaling (field-beam $\sigma_z$ varied,
tail source slice, 15 slices):

| $\sigma_{z,\text{field}}/\beta^*$ | 0.12 | 0.36 | 0.89 | 1.79 | 3.57 |
|---|---|---|---|---|---|
| $h_y$ ratio | 1.26 | 1.33 | 1.76 | 3.06 | 5.87 |

The horizontal barely moves because $\beta^*_x$ is an order of magnitude larger;
the blow-up is entirely in the small-$\beta^*$ plane, which for a flat beam is the
one that matters.

Measured emittance growth still *fell* with `:source_slice` (Section 11, arm F),
and that run included both directions and therefore the 2.7x penalty — so the
discontinuity removal won on net at `grid=(64,64)`. But the margin is much thinner
than the one-directional figures suggested, and the balance is **not** verified at
production grids, where the systematic $h^2$ term weighs more heavily against a
shot-noise-scale discontinuity.

**Rule of thumb:** safe below $\sigma_{z,\text{field}}/\beta^*_{\text{source}}
\approx 0.5$; measure above $\approx 1$.

The proper fix is not a larger or smaller union but a different *index*. Slices
$s$ and $s+1$ already share boundary node $z_s$, and Section 3.2's cancellation
works precisely because the right node of one and the left node of the other are
the same source drift. Making the mesh a function of the **node** rather than the
slice preserves that exactly: both sides of $z_s$ evaluate the same node on the
same mesh, at *every* boundary. Each node's mesh needs to cover only its own
single source drift and the two slices adjacent to it, so there is no union over
the field beam and no hourglass blow-up, at neutral cost. A bounded-group variant
(one mesh per $G$ adjacent slices) was considered and withdrawn: it only reduces
the jump from every transition to every $G$-th, for the same effort. The full
program — robust extent estimation, out-of-range safety, quantization, and node
indexing — is laid out in `todo.md`.

### 10.3 Deposition is the limiter — `:TSC` unlocks the full order

Section 9 predicted that the `:CIC` gain would be capped by the deposition's
smoothness, and that `:TSC` should do better because it is $C^1$ in the source
drift where `:CIC` is only $C^0$. Re-running the identical scan with
`deposit_method = :TSC` confirms it, by a much larger margin than anticipated:

| source slice | component | gain, `:CIC` | gain, `:TSC` |
|---|---|---|---|
| 4 | $\Delta p_x$ | 1.7 | **18.7** |
| 4 | $\Delta p_y$ | 7.3 | **36.5** |
| 4 | $\Delta p_z$ | 5.2 | **188** |
| 6 | $\Delta p_x$ | 5.5 | **45.0** |
| 6 | $\Delta p_y$ | 2.4 | **18.7** |
| 6 | $\Delta p_z$ | 5.2 | **105** |

And the longitudinal boundary discontinuity, the quantity of physical concern:

| deposition | `:linear` jump | `:quadratic` jump | reduction |
|---|---|---|---|
| `:CIC` | $0.52$ | $3.9\times10^{-2}$ | $13\times$ |
| `:TSC` | $0.55$ | $9.5\times10^{-4}$ | $580\times$ |

Two conclusions:

1. **The two options are multiplicative, not additive.** `:TSC` alone barely
   helps — its `:linear` longitudinal error ($0.277$) is close to `:CIC`'s
   ($0.332$), and its boundary jump is if anything slightly *worse* ($0.55$ vs
   $0.52$). `:quadratic` alone gives $5\times$. Together they give $100-190\times$
   and effectively eliminate the discontinuity, from $55\%$ of peak to $0.1\%$.
   Neither change is worth much without the other.
2. **The `:CIC` result was measuring the deposition floor, not the interpolation
   order.** With a $C^0$ charge deposit the third $\sigma$-derivative the quadratic
   relies on does not exist in the discrete field; the observed $5.2\times$ was
   the floor, not the method. This is the same mechanism that capped
   `field_derivative = :fourth` at $1.6\times$, and it is now quantified rather
   than inferred.

### 10.4 Node-indexed meshes — `interaction_grid = :node`

Sections 10.2's shared mesh removes the jump but pays the hourglass penalty
because it must span the whole field beam. Indexing the mesh by the interpolation
**node** avoids that entirely. Slices $s$ and $s+1$ share boundary node $z_s$, and
Section 3.2's cancellation works precisely because the right node of one and the
left node of the other are the same source drift; giving that node its own mesh
makes both sides read the same plane on the same mesh at *every* boundary.

Each node mesh covers only its own source drift (plus the next node's, see below)
and the two slices adjacent to it — no union over the field beam, hence no
hourglass sensitivity. Measured against the per-slice-pair meshes production
builds:

| quantity | per-slice-pair | `:source_slice` | `:node` |
|---|---|---|---|
| $\Delta p_x$ boundary jump | $1.0-1.6\times10^{-3}$ | $2.4\times10^{-9}$ | $1.1\times10^{-9}$ |
| $\Delta p_y$ boundary jump | $1.3-3.1\times10^{-3}$ | $1.9-3.0\times10^{-8}$ | $2.2-2.6\times10^{-8}$ |
| $h_x$ coarsening | 1.00 | 1.14-1.33 (2.7 in the other direction) | **1.11** |
| $h_y$ coarsening | 1.00 | 1.12-1.26 (2.70) | **1.05-1.08** |

and the turn cost is *lower* at production scale, because each node's Green FFT is
built once and reused by both adjacent slices:

| particles/beam | slices | grid | `:slice_pair` | `:node` | ratio |
|---|---|---|---|---|---|
| 100k | 15 | 64 | 2.886 s | 3.028 s | 1.05 |
| 1M | 15 | 128 | 24.389 s | 15.726 s | **0.64** |
| 50k (full lattice) | 15 | 64 | 1.184 s | 1.452 s | **1.23** |

**The ratio is operating-point dependent and should always be quoted with one.**
`:node` trades one extra field solve for a halving of Green-FFT builds, since each
node's mesh serves two slices. The Green FFT scales with grid size while the extra
solve scales with particle count, so `:node` wins at large grid and loses at small.

#### 10.4.1 Why the longitudinal pair must share a mesh

The first prototype put each of a slice's two planes on its own node mesh and the
longitudinal jump **exploded to $14\times$ the peak kick** — far worse than the
$0.52$ it started at. The cause is not a bug but a property of the quantity:

$$\Delta p_z \propto \phi_L - \phi_R$$

is a small difference of two large numbers, and its discretization error only
cancels when both planes are computed on the *same* mesh. Across meshes the
difference is wrong by $20-50\%$.

This was tested rather than assumed. If the discrepancy were a pure additive gauge
offset, subtracting a constant would fix it. Sampling it over a $5\times3$ grid of
transverse positions gives mean $5.1\times10^{-2}$ with standard deviation
$7.7\times10^{-2}$ — a **relative spread of 1.51**, so the discrepancy varies more
than its own mean and **no gauge fix exists**.

The implementation therefore performs three solves per slice-pair direction:

1. `F_L` — node $s$ at drift $\sigma_L$, on node $s$'s mesh;
2. `F_R` — node $s+1$ at drift $\sigma_R$, on node $s+1$'s mesh;
3. `F_Z` — node $s+1$ at drift $\sigma_R$, on **node $s$'s** mesh.

Transverse blends `F_L`/`F_R`, each read on its own mesh, giving exact continuity.
Longitudinal uses `F_L` and `F_Z`, which share a mesh, so `phi_L - phi_R` keeps its
error cancellation and the longitudinal jump stays at its usual sawtooth value
($0.55-0.65$, i.e. unchanged) rather than being corrupted. That is also why each
node mesh must cover the *next* node's drift as well as its own.

#### 10.4.2 Why three planes, and how many are actually distinct

Node mode has two requirements that conflict. Transverse continuity needs each
node's plane read on *that node's* mesh, so adjacent slices evaluate their shared
node identically. The longitudinal $\phi_L-\phi_R$ needs both values on *one*
mesh, or its discretization error stops cancelling. `:slice_pair` never faces this
because it puts every plane of a pair on one mesh — which is precisely why it has
the boundary discontinuity.

Resolving the conflict costs a third plane *per pair*, but not per crossing. Over
all $N$ field slices of one source slice:

| | planes |
|---|---|
| `:slice_pair` | $2N$ |
| `:node`, distinct planes | $(N+1)$ node $+\;N$ longitudinal $=2N+1$ |

Node planes are **shared between adjacent slices**: $F_R$ for slice $s$ *is* $F_L$
for slice $s+1$ — same node, same drift, same mesh, same source. There are only
$N+1$ distinct node planes. So the method costs **one extra solve per source
slice**, about 3% at $N=15$; an implementation that recomputes each node plane
twice pays $3N$ instead.

Realizing that saving would require accepting that $F_R$ is one step stale when
slice $s+1$ reuses it, since the source is kicked between the two pairs.

**This is rejected.** `:node` exists to remove a *numerical* discontinuity;
paying for it by freezing the source between two uses would trade away *physical*
strong-strong self-consistency, which defeats the option's purpose. The $3N$ cost
is accepted, and `:node`'s solve count is inherently $1.5\times$ the baseline's
$2N$. Remaining optimization must come from implementation overhead — mesh
prebuild and Green-FFT construction — not from the solve count.

#### 10.4.3 What is left

With the mesh term removed, the residual discontinuity is continuity breaker #3 of
Section 5 — the shared node is solved once per adjacent slice and the source is
kicked in between. Measured by applying one slice-pair's worth of kick to the
source and re-solving the same node on the same mesh:

| | $\Delta p_x$ | $\Delta p_y$ |
|---|---|---|
| residual source-evolution jump | $2.2\times10^{-5}$ | $7.6-8.1\times10^{-5}$ |

So node indexing lowers the transverse boundary discontinuity from $\sim10^{-3}$ to
a floor of $\sim10^{-4}$ set by a different mechanism — roughly $40\times$ — and
that floor is now the thing to attack next.

### 10.5 Mesh extent: estimator and quantization

Sections 10.2 and 10.4 fix *where* the mesh sits. Two further defects concern *how
big* it is, and they persist under every indexing scheme.

**The extent is a sample extremum.** For `n` particles per slice the maximum is
$\sigma\sqrt{2\ln n}$ with Gumbel fluctuation $\sigma/\sqrt{2\ln n}$ — an $O(1)$
statistic. Measured relative variation of the box
(`validation/pic_grid_extent_stability.jl`, 200k/beam, 15 slices, 8 turns):

| estimator | slice-to-slice $x$ / $y$ | turn-to-turn $x$ / $y$ | dropped |
|---|---|---|---|
| `:extrema` | $5.3\times10^{-2}$ / $5.1\times10^{-2}$ | $5.2\times10^{-2}$ / $4.8\times10^{-2}$ | 0 |
| `:sigma` ($k=6$) | $6.5\times10^{-3}$ / $1.3\times10^{-2}$ | $1.0\times10^{-2}$ / $1.4\times10^{-2}$ | 0 |

The predicted $\sim6-7\%$ extrema jitter is confirmed. `:sigma` is **4-8× stabler**,
against a prediction of $\ge10\times$ — the prediction was optimistic.

Crucially, `:sigma` addresses a *different* breaker than `:node`: node indexing
removes the slice-boundary jump exactly but does nothing about **turn-to-turn**
mesh jitter (Section 5, item 2). `:sigma` cuts that by $5\times$.

**A `:quantile` estimator was implemented, measured, and removed.** At a coverage
target tight enough to avoid charge loss ($1-10^{-5}$), the target rounds to *all*
particles for realistic slice populations ($n\approx13{,}000$), so it degenerates
to the extremum and adds histogram quantization noise on top — measured
$7.2\times10^{-2}$, i.e. **worse than `:extrema`**. Its useful regime needs loose
coverage, which the charge-loss arithmetic of Section 10.5.1 rules out. Shipping a
dominated public option would have been speculative surface.

#### 10.5.1 Why outlier rejection cannot be the sizing mechanism

Dropping a fraction $f$ of charge at radius $R$ costs a field error
$\sim f\,(\sigma/R)$. At $f=10^{-3}$, $R=5\sigma$ that is $2\times10^{-4}$ — the same
order as the $10^{-3}$ discontinuity the estimators exist to remove. Only
$f\lesssim10^{-5}$ is safe, i.e. an extent near $5.5-6\sigma$. Dropping is a
counted safety valve, not a sizing strategy.

That valve had to be built first. `_pic_cic_weights` **clamped the cell index while
keeping the weight**, so a particle outside the mesh deposited its full charge onto
the boundary cell — a spurious charge sheet, strictly worse than dropping it. On
CUDA a `NaN` coordinate produced a `NaN` weight that poisoned the entire charge
grid through the atomic add; on CPU the same input threw `InexactError` from inside
the kernel. Identical physics therefore **crashed loudly on CPU and silently
corrupted on GPU**. Both stencils on both backends now return zero weights outside
$[0, n-1]$ or for non-finite input, and the caller counts what was dropped.

#### 10.5.2 Quantization: nearly-equal is not equal

A mesh that differs by $1\%$ from its neighbour produces essentially the same
discretization jump as one that differs by $50\%$ — what matters is whether the
meshes are *identical*. `grid_quantize` snaps the extent to a $2^q$ ladder and the
origins to whole cells. Distinct meshes across 225 slice pairs (15×15, grid 64):

| configuration | distinct meshes |
|---|---|
| `:extrema`, no quantization | 225 |
| `:sigma`, no quantization | 225 |
| `:extrema`, $q=1/8$ | 29 |
| **`:sigma`, $q=1/8$** | **7** |

The two compose: `:sigma` alone collapses nothing (the box varies continuously),
quantization alone gives 29, together 7. For those pairs sharing a mesh the
discretization error cancels exactly, as it does under `:node`.

### 10.6 CUDA

`:node` is implemented on the CUDA sequential non-async route
(`batch_mode = :sequential`, `cuda_async = false`), with CPU parity $9.5\times10^{-16}$
and luminosity parity $2.7\times10^{-16}$. The wavefront and batched-FFT routes
assume one mesh per slice pair and throw rather than silently using the wrong one.

## 11. Does any of it move the dynamics? Mostly not

Everything in Section 10 is *field accuracy*. Whether it matters is a separate
question, and the `field_derivative = :fourth` precedent (Section 11 of the
2026-07-24 Poisson-solver review) is a standing warning that the two can be
unrelated.

`validation/slice_interpolation_emittance_growth.jl` measures it directly:
head-on collision, linear one-turn maps, no chromaticity or dispersion, and **no
radiation damping or excitation**, so the Poisson solver is the only
non-symplectic element and every bit of vertical emittance growth is numerical.
30k macroparticles/beam, `grid=(64,64)`, 800 turns, 4 seeds per arm (3 for the
30-slice arm). 47% of particles change slice index per turn (62% at 30 slices),
so the discontinuity is heavily sampled and a null result is meaningful.
`t` is the separation from baseline in pooled standard errors; $|t|<2$ is not
resolved. The electron is the sensitive probe ($Q_s=-0.069$ against the proton's
$-0.01$).

| scheme | slices | deposit | grid | electron $\varepsilon_y'$ | $t$ | proton $\varepsilon_y'$ | $t$ |
|---|---|---|---|---|---|---|---|
| `:linear` | 15 | CIC | slice_pair | $8.201\times10^{-5}$ | — | $3.273\times10^{-6}$ | — |
| `:quadratic` | 15 | CIC | slice_pair | $8.185\times10^{-5}$ | **−0.09** | $2.962\times10^{-6}$ | −1.10 |
| `:linear` | **30** | CIC | slice_pair | $8.464\times10^{-5}$ | **+1.56** | $3.082\times10^{-6}$ | −0.37 |
| `:linear` | 15 | **TSC** | slice_pair | $7.160\times10^{-5}$ | **−6.93** | $3.028\times10^{-6}$ | −0.91 |
| `:quadratic` | 15 | **TSC** | slice_pair | $7.057\times10^{-5}$ | **−5.22** | $2.746\times10^{-6}$ | −1.77 |
| `:linear` | 15 | CIC | **source_slice** | $7.591\times10^{-5}$ | **−3.44** | $2.291\times10^{-6}$ | **−2.79** |

1. **`:quadratic` does not reduce emittance growth.** $t=-0.09$ on the electron;
   not resolved. Nor does it add anything on top of `:TSC`. The `:fourth`
   precedent repeats exactly — a large field-accuracy gain with no dynamical
   consequence.
2. **Neither does doubling the slice count.** 30 slices costs $4\times$ and gives
   $t=+1.56$ — if anything marginally worse, certainly not better, even though the
   boundary-crossing fraction rises from 0.470 to 0.621 so the discontinuity is
   sampled *more*. This is the decisive control: it refines the interpolation
   error and the slicing error *simultaneously* (Section 6), and neither matters.
   **Longitudinal discretization is not the growth driver at all.**
3. **`deposit_method = :TSC` does** — 12.7% lower, $t=-6.93$, the largest effect
   measured.
4. **`interaction_grid = :source_slice` does** — 7.4% on the electron
   ($t=-3.44$) and 30% on the proton ($t=-2.79$); the only arm resolved on both,
   and it is also *faster* (Section 10.2).

**Field-accuracy metrics did not predict dynamics here, and the ranking is close
to inverted.** Section 10.3 rates `:quadratic`+`:TSC` a $100-190\times$
improvement in longitudinal field error, yet it is statistically
indistinguishable from `:TSC` alone in emittance growth; while `:TSC` alone,
which barely improves the `:linear` longitudinal field error, gives the biggest
dynamics improvement.

The coherent reading across all six arms: **artificial vertical emittance growth
in this configuration is driven by transverse field noise and mesh
discontinuity, not by longitudinal reconstruction error.** The two options that
move it — smoother deposition and a continuous mesh — both act on the transverse
field. The three that refine the longitudinal reconstruction — more nodes, more
slices, and both together — do nothing. Consistent with Section 11 of the
2026-07-24 Poisson-solver review.

## 12. Practical reading

- **Dynamics / emittance-growth work:** enable `deposit_method = :TSC` and
  `interaction_grid = :node`. `:node` supersedes `:source_slice`: it removes the
  same discontinuity with 1.05-1.11x coarsening instead of up to 2.70x, has no
  hourglass sensitivity, and is 36% *faster* at production scale. Do **not**
  enable `:quadratic` expecting a dynamics benefit — it does not deliver one.
- **Longitudinal field accuracy** (synchro-betatron detail, longitudinal
  diffusion, anything reading $\Delta p_z$ directly): enable `:quadratic`
  **together with** `:TSC`. Alone with `:CIC` it captures about a twentieth of
  the available gain, because the $C^0$ deposit, not the interpolation order, is
  the limiter. This is a field-accuracy justification, not a dynamics one.
- **On CUDA:** `:quadratic` costs $2.87\times$ the production default until the
  wavefront route can carry a third field plane. Prefer the CPU path (+5%).

## References

1. K. Hirata, H. Moshammer, and F. Ruggiero, "A symplectic beam-beam interaction
   with energy change", *Particle Accelerators* **40** (1993), 205-228.
2. J. Qiang, M. A. Furman, and R. D. Ryne, "A parallel particle-in-cell model for
   beam-beam interaction in high energy ring colliders", *J. Comput. Phys.* **198**
   (2004) 278.
3. R. W. Hockney and J. W. Eastwood, *Computer Simulation Using Particles*,
   McGraw-Hill (1981).
4. P. J. Davis, *Interpolation and Approximation*, Dover (1975), Ch. 3
   (Lagrange remainder and the minimax node placement used in Sections 7.3
   and 8).
