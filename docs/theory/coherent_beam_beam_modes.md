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

The on-axis gradient of a 2D Gaussian is $\partial_x K_x(0) \propto
1/(\sigma_x(\sigma_x+\sigma_y))$, which is **homogeneous of degree $-2$ in
$(\sigma_x,\sigma_y)$ jointly**. The $\sqrt2$ widening therefore halves it at
*every* aspect ratio, and the doubling restores it: $\Delta Q_\pi = \xi$, i.e.
the rigid Yokoya factor $Y \equiv \Delta Q_\pi/\xi$ is **exactly $1$ for round
and flat beams alike**. The rigid model freezes the distribution shape, which is
exactly what the beam-beam force does not allow, and that — not geometry — is
what the Vlasov treatment below corrects.

> **Correction (2026-08-05_b audit, U22-10).** This paragraph previously argued
> that for flat beams "the gradient scales as $1/\sigma_x$ (sheet-like field)"
> and concluded $Y_{\rm rigid} = 2/\sqrt2 = \sqrt2 \approx 1.41$, calling $Y$ a
> *geometry-dependent* number already at the rigid level. That is wrong twice
> over: $1/\sigma_x$ is dimensionally impossible for a 2D field gradient, and
> the degree-$-2$ homogeneity above holds regardless of flatness — verified at
> $\sigma_y/\sigma_x = 1,\ 0.5,\ 0.09,\ 0.02,\ 10^{-6}$, all giving
> $1.0000000$. It is not cosmetic: under $1.41$ this repository's own measured
> flat values ($1.2522$, $1.2657$ in §3) would sit *below* the rigid model,
> inverting the framing the whole benchmark rests on — that the Vlasov result
> *exceeds* the rigid one. `validation/coherent_beam_beam_modes.jl` and
> `validation/README.md` both already stated "rigid = 1" correctly, so the note
> contradicted the code it documents.

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
equilibrium (source-averaged) potential, normalized by the **analytic on-axis
gradient** that defines $\xi$.

> **Correction (2026-08-06, audit lead U26-4).** This paragraph previously said
> $\hat V_0$ is "normalized to $\hat V_0''(0) = 1$ so that the small-amplitude
> incoherent shift is exactly $\xi$", and the next one gave $u(0)=1$ and the
> continuum $[Q_0, Q_0+\xi]$. That is pre-fix text. Normalizing by the
> reduction's *own* averaged curvature is circular — it forces $u(0)=1$
> whatever the kernel does — which is precisely what the script's self-check 4
> removed, and $u(0)=1$ is now the signature that the circular normalization
> has come back. The implementing code asserts the opposite.

**Incoherent spectrum.** Averaging over angle gives the amplitude-dependent
tune $\omega(J) = Q_0 + \xi\,u(J)$ with $u(J) = 2\,d\langle\hat
V_0\rangle/dJ$ and $u\to0$ at large $J$, so the incoherent continuum is
$[Q_0,\,Q_0 + \xi\max u]$ (focusing sign; attractive $e^+e^-$).

The small-amplitude value is **below** $\xi$, and by a known factor: the
reduction convolves *both* beams' other-plane spreads into the kick
($s_t = \sqrt2\,r$) while $\xi$ is defined by the source's own $\sigma$, so

$$u(0) \;=\; \frac{1+r}{1+\sqrt2\,r},$$

which is $0.828$ at $r=1$ and approaches 1 only in the flat limit. Measured:
$\max u$ runs $0.827$ (round) to $0.990$ at $r=0.02$, against this expression
to better than $0.2\%$ — and `max u <= 1` is now asserted per row of the aspect
scan, because the quadrature defect corrected in §3 announced itself by
violating it (max $u$ reached 23.2).

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
$2N\times2N$ real matrix. Five structural checks validate every constant at
once (this list said "three" and omitted 4 and 5 — the two that changed the
physics — until audit lead U26-4; the script has carried five):

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
4. **Non-circular normalization:** the normalizing curvature must be the
   analytic on-axis gradient, not the reduction's own averaged curvature.
   Normalizing by the latter forces $u(0)=1$ whatever the kernel does, so the
   check reports $u(0)$ and requires it to match $(1+r)/(1+\sqrt2 r)$ — below
   1 and aspect-dependent. A value of exactly 1 means the circular
   normalization has returned. This is the check whose failure at flat aspect
   ratios was misread as a limit of the reduction; see §3.
5. **Harmonic assembly constants:** a harmonic interaction must give
   $\Lambda = 2$ exactly. For $V(u)=u^2/2$ the detuning vanishes and the $m=1$
   projection has the closed form $K(J,J') = -\sqrt{JJ'}/2$, which pins the
   $\varphi/\varphi'$ quadrature weights, the $1/(2\pi^2)$ projection factor
   and the $2\xi e^{-J}w'$ weighting against a closed form — independently of
   the Coulomb kernel and of check 4.

The discrete eigenvalue of the anti-symmetric sector above the continuum is
the $\pi$ mode; $Y = (\Omega_\pi - Q_0)/\xi$.

**Independent referee.** Because approximations enter the $m=1$ reduction,
the *same 1D-reduced model* is also solved by direct particle simulation
(`simulate_1d_model`): the averaged kernel has the exact Fourier transform
$\tilde G(k) = -i\pi\,\mathrm{sign}(k)\,e^{s^2k^2/2}\mathrm{erfc}(s|k|/\sqrt2)$
(the half-normal average of $e^{-|k||v|}$; an earlier version of this note
and script used a Gaussian suppression $e^{-s^2k^2/2}$ here, which is the
transform of smoothing along $u$, not of averaging over $v$ — corrected
2026-07-28 after external review), so the beam-beam
force is a smoothed Hilbert transform of the opposing line density, evaluated
spectrally each turn; two beams, rigid rotations, centroid FFTs — no code
shared with the matrix solve. Agreement between the two isolates model error
from solver error.

## 3. Results: the Vlasov band (symmetric beams)

Current numbers (`result/yokoya_vs_aspect.tsv`, regenerated 2026-08-05;
measured 2D column from `yokoya_vs_aspect_measured.tsv`; figure
`result/yokoya_vs_aspect.png`):

| $r=\sigma_y/\sigma_x$ | 1D model, m=1 matrix | 1D model, exact (sim) | full 2D PIC (measured) |
|---|---|---|---|
| 0.02–0.05 ‡ | 1.321 / 1.308 | 1.297 / 1.289 | 1.25 |
| 0.1  | 1.290 | 1.274 | **1.27** |
| 0.2–0.3   | 1.260 / 1.238 | 1.246 / 1.223 | 1.24 |
| 0.5       | 1.206 | 1.190 | 1.20 |
| 0.7       | 1.184 | 1.167 | — |
| 0.85      | 1.172 | 1.153 | — |
| 1.0 (round) | 1.162 | 1.143 | **1.19** |

‡ **Corrected 2026-08-06 (audit lead U22-1); this row previously read 23.2 /
5.51, and 0.1 previously read 1.923.** Those values were a quadrature
artifact, not physics. `gauss_avg` averaged over the source Gaussian with a
fixed 96-node Gauss-Hermite rule, whose node spacing is set by the *measure*
($0.320\,\sigma$, innermost node at $0.160\,\sigma$), while the integrand
carries all its structure on the scale $s_t=\sqrt2 r$ of the averaged plane.
Once $s_t \lesssim 0.3\,\sigma$ the rule stepped straight over the cusp, the
averaged potential's curvature at the origin came out too large, and $u(J)$ —
the entire diagonal of the eigenproblem — was wrong. That is why max $u$ ran
to 1.8–2.9 and *grew with NJ*: a finer $J$ grid sampled more of a diverging
$u(J)$. The rule is now a panel Gauss-Legendre whose panel width resolves
$s_t$; the values above are stable to five digits over a 4× panel-density
range and reproduce the shipped $r\ge0.2$ numbers unchanged.

The previous footnote read this artifact as a *physical* limit ("outside the
validated regime … characterizes the truncation, not the physics"). The
detection was right and the diagnosis was wrong, which is the expensive
failure mode: the anomaly was real, but its cause was the quadrature, so the
repair was a quadrature change rather than a caveat. Every row now satisfies
max $u \le 1$ (0.990 at $r=0.02$ falling to 0.827 at $r=1$) and carries a
discrete mode clear of the continuum by a uniform gap $\Lambda - \max u
\approx 0.33$; before the fix that gap was $\le 0.007$ for $r \le 0.1$, i.e.
the quoted "Yokoya factor" *was* the continuum top wearing a mode's name.
These three invariants — max $u \le 1$, the mode gap, and per-row translation
invariance — are now asserted per row by the script, which writes them into
`yokoya_vs_aspect.tsv` and refuses to label a band edge a Yokoya factor.

At $r = 0.02$ and $0.05$ the residual $\sigma$-drift ($2.9\times10^{-4}$,
$1.3\times10^{-4}$) is above the $10^{-4}$ floor the other rows meet; this is
the $J$-mesh, not the quadrature (`OCTOPUS_VLASOV_NJ=128 NPHI=160` brings
$r=0.02$ to $7.5\times10^{-5}$ and moves $\Lambda$ by $3\times10^{-4}$), so
those two rows carry fewer digits than the rest and are flagged
`mesh_limited` rather than suppressed.

An earlier correction, kept: the 2026-08-05 audit found the table's numbers
before *that* pass (0.86–1.40 matrix, "no discrete mode"–1.55 sim) were
pre-normalization-fix data the code no longer produced (audit queue
U19-1/U19-3).

Three conclusions, in decreasing order of certainty:

1. **The measured 2D curve is the physical answer** and lands inside the
   literature band with the right trend: $Y = 1.19$ round (confirmed at
   converged settings, 1.20, by the benchmark and by BeamBeam3D at
   1.197/1.210) rising to $\approx 1.25$-$1.27$ for flat beams (the
   EIC-like aspect $r=0.09$ point re-measured at 4x turns and 2.5x
   macroparticles reproduces $Y = 1.266$ exactly — the scan is converged) —
   the aspect-ratio dependence of Yokoya & Koiso, bounded by the anchors
   $\sim1.2$ (round, LHC/RHIC usage) and $\sim1.33$ (flat, KEKB usage).
2. **The m=1/diagonal truncation is accurate within the 1D model**
   (CORRECTED 2026-07-28: an earlier version claimed 10-25% truncation error,
   which was entirely an incorrect spectral kernel in the particle referee —
   see Section 2). With the correct kernel the matrix and the exact particle
   solution of the same model agree to 1-2% at **every** aspect ratio in the
   table: 1.8%, 1.5%, 1.2% at $r = 0.02, 0.05, 0.1$ and 1.1-1.7% from
   $r = 0.2$ to round. **Extended 2026-08-06 (U22-1)** — this statement
   previously carried the qualifier "wherever a discrete $\pi$ mode exists
   ($r \gtrsim 0.2$)", which existed only because the flat rows were broken.
3. **The 1D reduction is monotone and well-behaved across the whole range**,
   $\Lambda = 1.32$ (flat) $\to 1.16$ (round), and tracks the measured 2D
   curve to 2-4% except at round beams, where it sits ~2% low.

   **REFUTED and REPLACED 2026-08-06 (audit lead U22-1).** This conclusion
   previously read: *"The 1D reduction itself fails for flat beams: the exact
   1D-model solution loses the discrete $\pi$ mode below $r \approx 0.1$
   (buried in the continuum) … the vertical degree of freedom is not a
   spectator even for the horizontal mode."* That was inferred from the
   quadrature artifact corrected above, and two things refute it. First, the
   corrected matrix carries a discrete mode at every $r$ down to 0.02, clear
   of the continuum by the same gap (0.33) as at round beams. Second — and
   independently of the fix — the note's own "exact (sim)" column never lost
   the mode: it read 1.297 / 1.289 / 1.274 at $r = 0.02 / 0.05 / 0.1$ all
   along, within 2-4% of the measured 2D values, because the particle referee
   shares no code with the broken average. The table contradicted the
   conclusion drawn from it.

   What survives is weaker and worth keeping: the reduction is a 1-2%
   instrument, not a substitute for the full 2D computation, and the rigid-bunch
   diagnostic in Section 2 still runs 1.21-1.41 rather than 1. Quantitative $Y$
   for a specific machine still comes from the 2D Vlasov route or from direct
   simulation — which is what our benchmark provides.

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

Current coupled eigen-solve (`result/eic_coherent_modes.tsv`, regenerated
2026-08-05; figure `result/eic_coherent_modes.png`):

| plane | e continuum | p continuum | discrete modes outside both |
|---|---|---|---|
| x | $[0.080,\ 0.1650]$ | $[0.228,\ 0.2371]$ | none (top mode $0.23795$, at the **p**-continuum edge, $(Q-Q_p)/\xi_p = 1.06$) |
| y | $[0.140,\ 0.2126]$ | $[0.210,\ 0.2168]$ | **one: $0.22432$**, above BOTH continua, $(Q-Q_e)/\xi_e = 0.84$, $(Q-Q_p)/\xi_p = 1.52$ |

> **Correction (2026-08-06, audit lead U22-3).** The $x$ row previously read
> e-continuum $[0.080,\ 0.2549]$, p-continuum $[0.228,\ 0.2509]$, top mode
> $0.25488$ "at the e-continuum edge, $(Q-Q_e)/\xi_e = 1.98$". Every one of
> those numbers came from the same broken source average as §3 (the $x$-plane
> witness aspect ratios, 0.085 and 0.095, sit squarely in the failing regime):
> the continuum tops are $\xi\cdot\max u$, and $\max u$ was 1.98 / 2.45 instead
> of the analytic 0.965 / 0.969. The **conclusion is the one thing that
> survives** — still no discrete $x$ mode outside both continua — but the bands,
> the top mode and the stated reason do not, and after the repair the top $x$
> mode sits at the **proton** edge, not the electron one. The $y$ row is
> unchanged: its aspect ratios were on the converged side of the quadrature.

> **Correction (2026-08-05 audit, U19-2).** This section previously
> concluded "no coherent dipole mode detaches from the incoherent continua
> in either plane — every mode remains Landau-dampable", with the y-plane
> "marginal" (top eigenvalue at the e-continuum edge). The current
> eigen-solve — after the normalization fix the previous table predated —
> puts a discrete y-plane mode OUTSIDE both continua. The x-plane
> conclusion stands; the y-plane one does not: in this model that mode has
> no continuum to Landau-damp it, and the earlier "marginality" was
> understated. The caveats stand too: the y-plane sits in the coupled
> regime the 1D reduction is least trusted in, so this is a model
> prediction to check against strong-strong simulation, not a machine
> statement. `CoherentModePhysicsContract` continues to gate only the
> symmetric configuration while the EIC case is run as a demonstration.

**Strong-strong simulation comparison**
(`validation/coherent_mode_eic_comparison.jl`; figure
`result/eic_mode_comparison.png`; 4096 turns, 20k macroparticles/beam, both
beams kicked $0.1\sigma$ in both planes). The head-on equivalent run through
the real 2D PIC solver confirms the theory's structure and sharpens the
marginality into a measured effect:

| plane | prediction | measurement |
|---|---|---|
| x | responses confined to the two separated continua, Landau-damped | e peak $0.0955 \in [0.080, 0.168]$, p peak $0.231 \in [0.228, 0.237]$; broad structures; centroid decoherence in $\sim48$ turns (e) and $\sim112$ turns (p) |
| y | overlapping continua; top coupled mode *at* the e-continuum edge — marginal | **both beams lock onto one narrow persistent line at $0.2109$** (the proton bare tune, inside the band overlap), two decades above the rest of the spectrum, with **no measurable decoherence over 4096 turns** — while the same proton beam decoheres in 112 turns in x |

The factor $\gtrsim 40$ persistence contrast between the proton's x and y
centroids (equal $\xi_p$ in both planes) is a genuine collective effect: a
p-dominated two-beam mode at the lower edge of the proton band, weakly
damped despite lying inside the electron continuum — the electron content of
the mode is too small for electron Landau damping to absorb it efficiently.
In the real machine the electron radiation damping
($\tau \sim 2000$-$4000$ turns) acts on the electron admixture only, and the
proton beam has no damping of its own, so this is precisely the mode family
that coherent beam-beam studies for the EIC must track — reproduced here
from the production framework's own constants. (Caveats as above: head-on,
single slice, no crabbing or synchro-betatron coupling; the line position
and persistence, not growth rates, are the validated observables.)

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
