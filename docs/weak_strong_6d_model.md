# Weak–Strong Six-Dimensional Source Model

This note defines the source-bunch model used by weak–strong Gaussian
beam–beam tracking. The canonical longitudinal-kick derivation is given in
[Synchro-Beam Longitudinal Kick](beam_beam_longitudinal_kick.md); the present
note specifies which source moments enter those formulas and how a continuous
six-dimensional Gaussian is converted into thin longitudinal slices.

## 1. One thin source slice

A thin slice has one longitudinal coordinate and a four-dimensional
transverse Gaussian distribution in

$$
    \mathbf w=(x,p_x,y,p_y)^T.
$$

At the slice reference plane it is completely described by

$$
    \boldsymbol\mu_w
      =\langle\mathbf w\rangle,
    \qquad
    \Sigma_w
      =\operatorname{Cov}(\mathbf w,\mathbf w).
$$

It is useful to partition the covariance using
$\mathbf r=(x,y)^T$ and $\mathbf p=(p_x,p_y)^T$:

$$
    \Sigma_w
      =
      \begin{pmatrix}
        A_0&B_0\\
        B_0^T&Q_0
      \end{pmatrix},
$$

where the displayed block ordering is $(\mathbf r,\mathbf p)$. In the source
longitudinal coordinate $u$, transverse drift gives

$$
    A(u)
      =A_0+u(B_0+B_0^T)+u^2Q_0,
$$

and

$$
    A_u
      =B_0+B_0^T+2uQ_0.
$$

This single representation includes ordinary Twiss ellipses, transverse
$x$–$y$ coupling, a changing principal-axis angle, and the complete
$\sigma_{xy}$ contribution to the longitudinal kick.

An uncoupled Twiss description is only a convenience constructor for this
covariance. A transverse coupling map $R$ acts on it as

$$
    \Sigma_w\longmapsto R\Sigma_wR^T.
$$

The covariance, rather than the four coupling parameters themselves, is the
physical state of the strong slice.

The interaction-point-to-collision-point transformation is selected by the
named `virtual_drift` convention documented in Section 7 of
[Synchro-Beam Longitudinal Kick](beam_beam_longitudinal_kick.md). The default
is `:hirata`; `:chromatic` and `:exact` select the other Hamiltonian models.
Historical frozen variants are excluded from the physical symbol interface
and require an explicit `UnsafeVirtualDrift(...)` diagnostic wrapper.

## 2. A continuous six-dimensional Gaussian

Let the complete strong bunch be Gaussian in

$$
    \mathbf X=(x,p_x,y,p_y,z,p_z)^T
$$

with mean $\boldsymbol\mu$ and covariance

$$
    \Sigma
      =
      \begin{pmatrix}
        \Sigma_{ww}&\Sigma_{wz}&\Sigma_{wp_z}\\
        \Sigma_{zw}&\Sigma_{zz}&\Sigma_{zp_z}\\
        \Sigma_{p_zw}&\Sigma_{p_zz}&\Sigma_{p_zp_z}
      \end{pmatrix}.
$$

Longitudinal slicing by $z$ requires the conditional, not projected,
transverse distribution. For a delta-like slice at $z=z_i$,

$$
    \boldsymbol\mu_{w\mid z_i}
      =
      \boldsymbol\mu_w
      +
      \frac{\Sigma_{wz}}{\Sigma_{zz}}
      (z_i-\mu_z),
$$

and

$$
    \Sigma_{w\mid z}
      =
      \Sigma_{ww}
      -
      \frac{\Sigma_{wz}\Sigma_{zw}}{\Sigma_{zz}}.
$$

For a joint Gaussian the conditional covariance is independent of $z_i$.
Consequently, all ideal delta slices share the same transverse covariance but
have different four-dimensional centroids.

## 3. Crab and momentum dispersion

Consider the linear model

$$
    \mathbf w
      =
      \mathbf w_\beta
      +\boldsymbol\zeta z
      +\boldsymbol\eta p_z,
$$

where $\mathbf w_\beta$ is independent of the longitudinal coordinates,
$\boldsymbol\zeta$ is crab dispersion, and $\boldsymbol\eta$ is momentum
dispersion. Let

$$
    L=
      \begin{pmatrix}
        \sigma_z^2&\sigma_{zp_z}\\
        \sigma_{zp_z}&\sigma_{p_z}^2
      \end{pmatrix}.
$$

Conditioning on $z$ gives the slice-centroid slope

$$
    \frac{d\boldsymbol\mu_{w\mid z}}{dz}
      =
      \boldsymbol\zeta
      +
      \boldsymbol\eta
      \frac{\sigma_{zp_z}}{\sigma_z^2},
$$

and the within-slice covariance

$$
    \Sigma_{w\mid z}
      =
      \Sigma_\beta
      +
      \boldsymbol\eta\boldsymbol\eta^T
      \left(
        \sigma_{p_z}^2
        -\frac{\sigma_{zp_z}^2}{\sigma_z^2}
      \right).
$$

These equations resolve the different roles of the two dispersions:

- Pure linear crab dispersion changes only the centroid and angle of each
  delta slice. It does not change the conditional slice size.
- Momentum dispersion generally increases and couples the within-slice
  covariance because the slice still contains an energy distribution.
- A nonzero $z$–$p_z$ covariance makes momentum dispersion contribute to the
  slice-centroid slope as well.

Momentum dispersion can be ignored only when it is absent, when the remaining
conditional energy spread vanishes, or when the required accuracy justifies
discarding its contribution to $\Sigma_{w\mid z}$.

## 4. Finite bins and thin representatives

The conditional formulas above describe a slice at one exact $z$. A numerical
bin has a finite conditional variance
$\operatorname{Var}(z\mid\text{bin})$. If a thin representative must preserve
the covariance of every finite bin, its transverse covariance receives the
additional term

$$
    \frac{\Sigma_{wz}\Sigma_{zw}}{\Sigma_{zz}^2}
    \operatorname{Var}(z\mid\text{bin}).
$$

The delta-slice approximation omits this term and represents the longitudinal
line density by weighted point slices. This is consistent with the
synchro-beam construction. A finite-bin moment model should retain the term
explicitly rather than disguising it as an empirical slice-size modulation.

## 5. Model boundary

A sliced Gaussian moment model is closed under linear transport. It is not a
complete representation when any of the following is important:

1. non-Gaussian transverse structure within a slice;
2. nonlinear dependence of transverse coordinates on $z$ or $p_z$;
3. source evolution during a collision that cannot be represented by updated
   first and second moments; or
4. exact momentum-dependent drift requiring averages of nonlinear functions
   such as $p_x/(1+p_z)$.

Those cases require a Gaussian mixture, higher slice moments, or a
macroparticle/PIC source. The model should be selected by the required physics,
not by adding unrelated flags to a thin Gaussian element.

## 6. Turn-dependent modulation

Turn schedules, noise processes, feedback, and externally supplied time series
are workflow state rather than properties of a beam–beam collision. They
should be represented by scheduled task actions that update a source model at
turn boundaries. Keeping them outside the thin-slice runtime object has three
benefits:

1. the collision kernel remains type-stable and GPU compatible;
2. stochastic state and reproducibility belong to the task that owns them;
3. arbitrary modulation can be composed without expanding the beam element
   with a separate signal type for every observable.

## References

1. K. Hirata, H. Moshammer, and F. Ruggiero, “A symplectic beam-beam
   interaction with energy change,” *Particle Accelerators* **40** (1993),
   205–228.
   <https://research.kek.jp/people/dmzhou/BeamPhysics/SAD/Beam-beam_Hirata-1992.pdf>

2. L. H. A. Leunissen, F. Schmidt, and G. Ripken, “Six-dimensional beam-beam
   kick including coupled motion,” *Physical Review Special Topics –
   Accelerators and Beams* **3**, 124002 (2000).
   <https://doi.org/10.1103/PhysRevSTAB.3.124002>

3. XSuite, `BeamBeamBiGaussian3D` documentation and pinned covariance-transport
   implementation.
   <https://xsuite.readthedocs.io/en/stable/beambeam.html>
   <https://github.com/xsuite/xfields/blob/a9a44039e1fc8054aaf7a676089b8e61ccb8bd15/xfields/beam_elements/beambeam_src/beambeam3d_transport_sigmas.h>

4. J. Qiang *et al.*, “Parallel strong-strong/strong-weak simulations of
   beam-beam interaction in hadron accelerators,” LBNL-53638 (2003).
   <https://digital.library.unt.edu/ark:/67531/metadc781155/>
