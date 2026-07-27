# Coherent Beam-Beam Dipole Modes: the Vlasov Band and the Yokoya Factor

Theory note behind `validation/coherent_mode_vlasov_theory.jl` (the
linearized-Vlasov eigenproblem and the 1D particle referee),
`validation/coherent_mode_scans.jl` (measured 2D strong-strong scans), the
benchmark `validation/coherent_beam_beam_modes.jl`, and
`CoherentModePhysicsContract`. Figures are written to `result/`
(`yokoya_vs_aspect.png`, `yokoya_vs_xi.png`, `eic_coherent_modes.png`) by
`validation/plot_coherent_mode_theory.py`.

## 1. The rigid-bunch model, and why it is only the starting point

Two identical bunches collide head-on at one IP; consider one transverse
plane. If each bunch is a rigid Gaussian of rms $\sigma$ displaced by its
barycenter, the coherent kick on beam 1 depends on the separation
$\Delta = \bar x_1 - \bar x_2$ through the field of a Gaussian of width
$\sqrt{2}\sigma$ (the convolution of the two shapes). Writing $\xi$ for the
incoherent small-amplitude tune shift, the linearized barycenter map has two
eigenmodes:

- the **$\sigma$ mode** ($\bar x_1 = \bar x_2$): the separation never changes,
  no net force, tune exactly $Q_0$;
- the **$\pi$ mode** ($\bar x_1 = -\bar x_2$): each barycenter sees twice its
  own displacement through a force gradient reduced by the $\sqrt2$-wider
  effective Gaussian.

For **round** beams the 2D field gradient scales as $1/\sigma^2$, so the
$\sqrt2$ widening halves it and the doubling restores it:
$\Delta Q_\pi = \xi$, i.e. the rigid Yokoya factor $Y \equiv \Delta Q_\pi/\xi$
is exactly $1$. For **flat** beams the gradient scales as $1/\sigma_x$
(sheet-like field), so the same argument gives $Y_{\rm rigid} = 2/\sqrt2 =
\sqrt2 \approx 1.41$. The rigid model already shows that $Y$ is a
*geometry-dependent* number — but it freezes the distribution shape, which is
exactly what the beam-beam force does not allow.

## 2. Linearized Vlasov eigenproblem (symmetric collision)

Per beam and per plane, use action-angle variables of the bare lattice,
$x = \sqrt{2J}\cos\varphi$ in units of the beam's own rms size, equilibrium
$f_0 = e^{-J}/2\pi$, bare tune $Q_0$, smooth-focusing approximation (one IP,
kick treated as a continuous perturbation — valid for $\xi \ll 1$ away from
low-order resonances).

**The 1D-reduced interaction.** The 2D Coulomb kick between a witness at
$(x, y_w)$ and a source particle at $(x', y_s)$ is averaged over both
vertical Gaussians. With $s^2 = \sigma_{y,w}^2 + \sigma_{y,s}^2$ (in
horizontal-sigma units, $s = \sqrt2\, r$ for equal beams of flatness
$r=\sigma_y/\sigma_x$) the averaged kick has the closed form

$$G(u) \;=\; \Big\langle \frac{u}{u^2+v^2} \Big\rangle_{v\sim N(0,s)}
 \;=\; \mathrm{sign}(u)\,\sqrt{\tfrac{\pi}{2}}\,\frac{1}{s}\,
 \mathrm{erfcx}\!\Big(\frac{|u|}{\sqrt2 s}\Big),$$

with $\mathrm{erfcx}(z) = e^{z^2}\mathrm{erfc}(z)$. Note the **step at
$u=0$** (the sheet-beam limit); every numerical integral in the
implementation splits this non-smooth part off analytically — naive Gaussian
quadrature across the step is what initially produced a wrong incoherent
normalization ($u(0) \ne 1$), caught by the self-checks below. The kick
potential is $W(u) = \int_0^u G$, and the per-turn Hamiltonian perturbation is
$H_1 = 2\xi\,[\hat V_0(x) + \delta\hat V(x,\theta)]$, where $\hat V_0$ is the
equilibrium (source-averaged) potential normalized to $\hat V_0''(0) = 1$ so
that the small-amplitude incoherent shift is exactly $\xi$.

**Incoherent spectrum.** Averaging over angle gives the amplitude-dependent
tune $\omega(J) = Q_0 + \xi\,u(J)$ with $u(J) = 2\,d\langle\hat
V_0\rangle/dJ$, $u(0)=1$, $u\to0$ at large $J$: the incoherent continuum
$[Q_0,\,Q_0+\xi]$ (focusing sign; attractive $e^+e^-$).

**Coherent perturbation.** Write $f_1 = g(J)\,e^{i(\varphi-\Omega\theta)}$
(the $m=1$ dipole harmonic; the $m=-1$ sideband and the angle-dependent part
of the equilibrium force are dropped — the standard leading-order
approximation, checked against particle simulation of the same model below).
Projecting the perturbed potential of the *other* beam onto $m=1$ yields the
coupled eigenproblem

$$\big(\Omega - \omega(J)\big)\,g_a(J) \;=\;
 2\xi\, e^{-J} \int_0^\infty K(J,J')\,g_b(J')\,dJ',$$

$$K(J,J') = \frac{1}{2\pi^2}\int_0^{2\pi}\!\!d\varphi\int_0^{\pi}\!\!d\varphi'
 \,\cos\varphi\,\cos\varphi'\;\hat V_{\rm pt}\big(x(J,\varphi) -
 x'(J',\varphi')\big),$$

with $\hat V_{\rm pt} = W/N_0$ the point-kick potential under the same
normalization. Discretizing $J$ on Gauss-Legendre nodes turns this into a
$2N\times2N$ real matrix. Three structural checks validate every constant at
once:

1. **Translation invariance:** the co-moving rigid displacement
   $g_{\rm rigid}(J) \propto \sqrt{2J}\,e^{-J}$ must be an eigenvector at
   exactly $Q_0$ (a uniform shift of both beams changes nothing). The
   implementation reaches $|\Omega_\sigma - Q_0| \lesssim 10^{-5}\xi$.
2. **Harmonic-interaction limit:** replacing $W$ by $u^2/2$ makes the kernel
   rank-one and the problem solvable by hand: the anti-mode lands at exactly
   $Q_0 + 2\xi$ ($Y=2$), as it must for a linear force (no shape deformation
   possible, coherent slope equals incoherent slope, separation doubles).
   The code reproduces this analytically and numerically.
3. **$\xi$-independence:** at leading order both the detuning and the
   coupling scale with $\xi$, so $Y$ must not depend on it; verified.

The discrete eigenvalue of the anti-symmetric sector above the continuum is
the $\pi$ mode; $Y = (\Omega_\pi - Q_0)/\xi$.

**Independent referee.** Because approximations enter the $m=1$ reduction,
the *same 1D-reduced model* is also solved by direct particle simulation
(`simulate_1d_model`): the averaged kernel has the exact Fourier transform
$\tilde G(k) = -i\pi\,\mathrm{sign}(k)\,e^{-s^2k^2/2}$, so the beam-beam
force is a smoothed Hilbert transform of the opposing line density, evaluated
spectrally each turn; two beams, rigid rotations, centroid FFTs — no code
shared with the matrix solve. Agreement between the two isolates model error
from solver error.

## 3. Results: the Vlasov band (symmetric beams)

First-run numbers (`result/yokoya_vs_aspect.tsv`,
`yokoya_vs_aspect_measured.tsv`; figure `result/yokoya_vs_aspect.png`):

| $r=\sigma_y/\sigma_x$ | 1D model, m=1 matrix | 1D model, exact (sim) | full 2D PIC (measured) |
|---|---|---|---|
| 0.02–0.05 | 0.86–0.91 (buried) | no discrete mode | 1.25 |
| 0.09–0.1  | 0.89 | 0.66 | **1.27** |
| 0.2–0.3   | 1.10–1.26 | 1.29–1.50 | 1.24 |
| 0.5       | 1.35 | 1.55 | 1.20 |
| 1.0 (round) | 1.40 | 1.25 | **1.19** |

Three conclusions, in decreasing order of certainty:

1. **The measured 2D curve is the physical answer** and lands inside the
   literature band with the right trend: $Y = 1.19$ round (confirmed at
   converged settings, 1.20, by the benchmark and by BeamBeam3D at
   1.197/1.210) rising to $\approx 1.25$-$1.27$ for flat beams (the
   EIC-like aspect $r=0.09$ point re-measured at 4x turns and 2.5x
   macroparticles reproduces $Y = 1.266$ exactly — the scan is converged) —
   the aspect-ratio dependence of Yokoya & Koiso, bounded by the anchors
   $\sim1.2$ (round, LHC/RHIC usage) and $\sim1.33$ (flat, KEKB usage).
2. **The m=1/diagonal truncation is not quantitatively reliable**: against
   the exact particle solution *of the same 1D model* it errs by 10-25% with
   an $r$-dependent sign. This is measured here, not assumed — most compact
   treatments stop at m=1 and inherit this error silently.
3. **The 1D reduction itself fails for flat beams**: the exact 1D-model
   solution loses the discrete $\pi$ mode below $r \approx 0.1$ (buried in
   the continuum), while the real 2D system measurably keeps a healthy
   discrete mode at $Y \approx 1.25$ there. The vertical degree of freedom is
   not a spectator even for the horizontal mode. Quantitative $Y$ therefore
   requires either the full 2D Vlasov computation (Yokoya-Koiso's original
   route) or direct simulation — which is what our benchmark provides, now
   with theory-grade structural checks around it.

**$Y$ versus $\xi$** (`result/yokoya_vs_xi.png`): the measured PIC scan gives
$Y = 1.183,\ 1.188,\ 1.185,\ 1.152$ at $\xi = 0.0025, 0.005, 0.01, 0.02$ —
$\xi$-independent to $\pm0.5\%$ through $\xi = 0.01$, confirming the
leading-order statement. At $\xi = 0.02$ the discrete-map correction (below)
predicts a *positive* shift ($+0.04$ at $Q_0=0.31$), while the measurement
dips by $-0.036$: higher-order collective effects beyond both leading-order
Vlasov and the rigid-map algebra dominate the correction at the few-percent
level, with opposite sign. The "Vlasov band" is thus robust in $\xi$ for
practical parameters, with corrections entering only above $\xi \sim 0.01$.

**$Y$ versus $\xi$.** At leading order $Y$ is $\xi$-independent; the visible
$\xi$-dependence at finite $\xi$ comes from the discreteness of the one-turn
map. Inserting the Vlasov $Y_0$ into the exact rigid map algebra gives

$$\cos 2\pi Q_\pi = \cos 2\pi Q_0 - 2\pi Y_0\,\xi\,\sin 2\pi Q_0
\;\;\Rightarrow\;\;
Y_{\rm eff}(\xi) = \frac{\arccos(\cdot)/2\pi - Q_0}{\xi},$$

a weak, $Q_0$-dependent drift of order $\pi Y_0^2 \cot(2\pi Q_0)\,\xi$
(for $Q_0 = 0.31$: $\Delta Y \approx -0.01$ at $\xi=0.005$, $-0.04$ at
$\xi=0.02$), compared against the measured PIC $\xi$ scan in
`result/yokoya_vs_xi.png`.

## 4. The asymmetric (EIC-like) case

For two different beams the $\sigma/\pi$ classification is lost: with tunes
$Q_e \ne Q_p$ and parameters $\xi_e \ne \xi_p$ the modes are eigenvectors of
the full coupled system

$$\big(\Omega-\omega_e(J)\big)g_e = 2\xi_e e^{-J}\!\int\!K_{ep}\,g_p,\qquad
\big(\Omega-\omega_p(J)\big)g_p = 2\xi_p e^{-J}\!\int\!K_{pe}\,g_e,$$

where the cross kernels carry each beam's own geometry (the EIC-relevant
generalization: the witness normalization runs over its own sigma, the
separation over both). Using the strong-strong example constants
(10 GeV e / 275 GeV p, $\sigma_e = (106, 9.5)\,\mu$m,
$\sigma_p = (95, 8.5)\,\mu$m, tunes $e\,(0.08, 0.14)$, $p\,(0.228, 0.210)$):

- $\xi_e^x \approx 0.088$, $\xi_p^x \approx 0.0094$: the $x$ tune split
  ($0.148$) exceeds both parameters — weak-coupling regime;
- $\xi_e^y \approx 0.100$, $\xi_p^y \approx 0.0094$: the $y$ split ($0.07$)
  is **smaller than $\xi_e$** — the electron continuum overlaps the proton
  tune. This is the structurally interesting plane.

First-run coupled eigen-solve (`result/eic_coherent_modes.tsv`, figure
`result/eic_coherent_modes.png`):

| plane | e continuum | p continuum | discrete modes outside both |
|---|---|---|---|
| x | $[0.080,\ 0.155]$ | $[0.228,\ 0.236]$ | none |
| y | $[0.140,\ 0.240]$ | $[0.210,\ 0.219]$ (inside e band) | none; top eigenvalue $0.2415$, i.e. at the e-continuum edge, $(Q-Q_e)/\xi_e = 1.01$ |

The physics conclusion mirrors the RHIC/LHC experience with split tunes
(White et al.): with the working points separated by more than the
proton's $\xi_p$, no coherent dipole mode detaches from the incoherent
continua in either plane — every mode remains Landau-dampable. The $y$ plane
is the marginal case: the electron continuum swallows the proton tune, and
the topmost coupled mode sits *at* the electron continuum edge rather than
clearly above it, so modest parameter changes (higher $\xi_e$, smaller tune
split, weaker damping) could detach it. That marginality — not a single
Yokoya number — is the actionable output for the asymmetric case, and it is
why `CoherentModePhysicsContract` gates only the symmetric configuration
while the EIC case is run as a demonstration.

Caveats for the EIC application, in honesty: the theory model is head-on and
single-slice (no crossing angle, crabbing, hourglass, or synchro-betatron
sidebands), radiation damping of the electron beam ($\tau \sim 4000$ turns,
rate $2.5\times10^{-4}$/turn) is comparable to fine mode splittings and will
damp weakly-detached modes, and the smooth-focusing approximation drops
resonance effects. The model is the right tool for locating continua and
strong discrete modes, not for quantitative growth rates.

## 5. References

- K. Yokoya, H. Koiso, "Tune shift of coherent beam-beam oscillations",
  Part. Accel. 27 (1990) 181.
- W. Herr, T. Pieloni, "Beam-Beam Effects", CAS lecture, arXiv:1601.05235
  (the $\pi$-mode shifted by $1.2$-$1.3\,\xi$, aspect-ratio dependent; rigid
  models underestimate the round-beam value).
- Y. Alexahin, "A study of the coherent beam-beam effect in the framework of
  the Vlasov perturbation theory", NIM A 480 (2002) 253.
- R.E. Meller, R.H. Siemann, IEEE Trans. Nucl. Sci. NS-28 (1981) 2431 (rigid
  two-beam modes).
- S. White et al., "Coherent beam-beam experiments and implications for
  head-on compensation", arXiv:1410.5623 (RHIC; the kick-and-FFT method used
  by our benchmark).
