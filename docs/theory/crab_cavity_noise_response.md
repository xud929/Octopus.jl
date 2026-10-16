# Crab Cavity RF Noise on a Colliding Beam: Kick Errors, IP Offsets and Emittance Growth

This note derives the response of a weak proton beam to turn-by-turn phase
and amplitude noise on its crab cavities while it collides with a rigid
Gaussian strong beam, and sizes the measurement that checks the
turn-modulation rules against that response. It answers four questions: how
large a transverse kick error a per-turn phase or strength offset on one
harmonic of a thin crab cavity produces; how that error maps onto an orbit
offset at the interaction point (IP); how fast the rms emittance grows under
white and coloured offset sequences; and what the rigid strong beam adds.

The crab-cavity-noise example in `examples/` and the validation script
`validation/crab_cavity_noise_response.jl` use it; both are added by the
campaign this note opens, and at the note's first commit neither exists yet.
The numbers they measure belong to the campaign's record under
`docs/history/`, not to this note. The rules themselves (white, pink, table,
their offset semantics, additive on a phase and relative on a strength since
2026-10-15, and their measured spectra) are designed in
[Turn-by-turn lattice modulation](../design/turn_modulation.md), sections
5.1, 5.2, 5.5 and 5.6; the strong-beam model is the
[Weak–Strong Six-Dimensional Source Model](weak_strong_6d_model.md); the
beam-line is the EIC weak–strong case of `examples/weak_strong_tracking.jl`.

## Production point (the owner's specification)

- RF phase noise of rms $\sigma_\phi = 10\ \mu\text{rad}$ and relative
  amplitude noise of rms $\sigma_A = 10^{-4}$ on the proton crab cavities of
  the EIC weak–strong case.
- Rules under test: `WhiteNoise`, `PinkNoise` (Voss–McCartney, 16 octaves)
  and `TurnTable` (a recorded sequence), all at the same rms.
- Interpretation adopted here and flagged for the owner (section 8):
  (i) 10 µrad applies to **each active harmonic cavity independently**
  (separate LLRF systems, independent streams); the alternative is a common
  timing jitter, under which harmonic $i$ sees $i$ times the fundamental's
  phase noise and the two harmonics' kick errors are fully correlated
  (section 2.4: the rate changes by the factor 0.59); (ii) the amplitude
  rule's sigma is the relative rms $10^{-4}$ itself, one dimensionless factor
  $1 + d$ scaling both planes' strengths of the harmonic, so the absolute
  horizontal error is $10^{-4}\,|\texttt{strengthX}_i|$ and the vertical one
  $10^{-4}\,|\texttt{strengthY}_i| = 0$ (owner decision 2026-10-15, section
  3.2; until then the shipped rule added the absolute offset
  $10^{-4}\,|\texttt{strengthX}_i|$ to both planes); (iii) the two cavities,
  a quarter betatron wavelength before and after the IP, carry independent
  streams.

## 1. Model and assumptions

| symbol | meaning | value |
|---|---|---|
| $E$, $\gamma$ | proton energy, Lorentz factor | 275 GeV, 293.09 |
| $r_p = r_e m_e/m_p$ | classical proton radius | $1.5347\times10^{-18}$ m |
| $N_s$ | strong (electron) bunch population | $1.7203\times10^{11}$ |
| $\sigma_x^*,\ \sigma_y^*$ | IP rms sizes, both beams | 95 µm, 8.5 µm |
| $\beta_x^*,\ \beta_y^*$ | IP beta functions, $\alpha^* = 0$ | 0.8 m, 0.072 m |
| $\varepsilon_x,\ \varepsilon_y = \sigma^{*2}/\beta^*$ | geometric rms emittances | $1.128\times10^{-8}$ m, $1.004\times10^{-9}$ m |
| $\sigma_z,\ \sigma_\delta$ | weak bunch length, momentum spread | 6 cm, $6.6\times10^{-4}$ |
| $\beta_{cc,x},\ \beta_{cc,y}$ | beta functions at both crab cavities, $\alpha = 0$ | 1300 m, 100 m |
| $\theta_c$ | half crossing angle | 12.5 mrad |
| $f,\ k = 2\pi f/c$ | crab fundamental, wavenumber | 197 MHz, 4.1288 m⁻¹ ($2k = 8.2576$ m⁻¹) |
| $k\sigma_z,\ 2k\sigma_z$ | rms bunch phase per harmonic | 0.2477, 0.4955 |
| $w_i$ | harmonic weights | $(4/3,\ -1/3,\ 0)$ |
| $s_i = w_i \tan\theta_c/\sqrt{\beta_x^*\beta_{cc,x}}$ | `strengthX[i]` | $5.1684\times10^{-4}$, $-1.2921\times10^{-4}$, 0 m⁻¹ |
| $Q_x,\ Q_y,\ Q_s$ | tunes (the example's synchrotron tune is $-0.01$; only its magnitude enters) | 0.228, 0.210, 0.01 |
| $\xi'_x,\ \xi'_y$ | chromaticities | 2, 2 |
| $C,\ f_{\rm rev} = \beta c/C$ | circumference (owner-given), revolution frequency | 3833.8 m, 78 196.75 Hz ($\beta = 0.99999418$) |

The thin crab cavity map, as coded in `src/elements/crab_cavity.jl`, applies
for each harmonic $i = 1..N$

$$
\Delta p_x = -\frac{s_i}{ik}\sin(ikz+\phi_i),\qquad
\Delta p_y = -\frac{s_{y,i}}{ik}\sin(ikz+\phi_i),\qquad
\Delta p_z = -(s_i x + s_{y,i} y)\cos(ikz+\phi_i),
$$

with $x$, $y$, $z$ unchanged; $p_{x,y}$ are the transverse momenta in units
of the reference momentum (radians), $s_i$ is in m⁻¹, $\phi_i$ in radians.
The two active harmonics are separate cavities; harmonic 3 is inactive. The
`realize` method of the `CrabCavityNoise` container adds the realised phase
offset to `phase[i]` and scales **both** `strengthX[i]` and `strengthY[i]`
by the realised factor $1 + d_i$ (the relative semantics of 2026-10-15,
section 3.2; before that date it added one absolute offset to both), once
per turn on the host, before the turn is tracked.

Assumptions:

1. The ring is linear: `Linear6D` one-turn map with the tunes above, a
   chromaticity kick, and the cavity–IP telescopes with phase advance
   $\pi/2$ in $x$ and $0$ in $y$ (`dmu = (π/2, 0, 0)`), $\alpha = 0$ at both
   ends. The lumped radiation element with `damping_turns = 1e100` and
   excitation only has excitation scale $\sqrt{-\mathrm{expm1}(-2/\tau)}
   \approx 1.4\times10^{-50}$: inert.
2. The strong beam is a rigid Gaussian centred on the design orbit, seven
   longitudinal slices with the Hirata virtual drift; in the boosted frame
   the crabbed collision is head-on, so a transverse displacement of the
   weak bunch at the IP is a displacement relative to the strong beam.
3. Noise is sampled once per turn, additive on `phase[i]` (rad) or a
   dimensionless relative factor $d$ on both `strengthX[i]` and
   `strengthY[i]` (the absolute strength error is $s_i d$, in m⁻¹),
   independent across cavities (distinct `rng_id`) and across harmonics
   (distinct slots of one `rng_id`), Gaussian with the stated ensemble rms.
4. Small-offset regime: offsets much smaller than $\sigma^*$ and total
   growth over a run much smaller than $\varepsilon$; the response is linear
   in $\delta\phi$ and $\delta s$.
5. Ensemble averages are over the matched Gaussian weak beam, with $(x,p_x)$
   independent of $(z,\delta)$ at the cavities.

## 2. The kick error from a phase offset

### 2.1 First order in $\delta\phi$: dipole part and residual

Expanding the coded kick of harmonic $i$ at $\phi_i = 0$,

$$
\Delta p_x^{(i)}(\delta\phi) - \Delta p_x^{(i)}(0)
 = -\frac{s_i}{ik}\left[\sin(ikz+\delta\phi)-\sin(ikz)\right]
 = -\frac{s_i\,\delta\phi}{ik}\cos(ikz) + O(\delta\phi^2)
 = \underbrace{-\frac{s_i\,\delta\phi}{ik}}_{\text{dipole}}
   \;+\;\underbrace{\frac{s_i\,\delta\phi}{ik}\bigl(1-\cos ikz\bigr)}_{\text{residual}} .
$$

The dipole part is the same for every particle; the residual is
$\simeq (s_i\delta\phi/ik)(ikz)^2/2$ and varies along the bunch. Over the
Gaussian bunch

$$
\langle\cos ikz\rangle = e^{-(ik\sigma_z)^2/2},\qquad
\langle\cos^2 ikz\rangle = \tfrac12\bigl(1+e^{-2(ik\sigma_z)^2}\bigr),
$$

| $i$ | $\langle\cos ikz\rangle$ | $\langle\cos^2 ikz\rangle$ | residual rms / dipole |
|---|---|---|---|
| 1 | 0.9698 | 0.9422 | 0.043 |
| 2 | 0.8845 | 0.8060 | 0.174 |

The energy kick acquires the error $+s_i x\,\delta\phi\sin(ikz)$, of
relative size $\delta\phi\,ik\sigma_z \approx 2.5\times10^{-6}$ against the
nominal $\Delta p_z$: inert. The second-order term rescales the nominal
crabbing by $\delta\phi^2/2 = 5\times10^{-11}$: inert.

### 2.2 Propagation to the IP: the upstream cavity

A kick $\theta$ at a point with $\beta_1$, $\alpha_1 = 0$ arrives at a point
with $\beta_2$, $\alpha_2 = 0$ after phase advance $\psi$ as
$\Delta x = \sqrt{\beta_1\beta_2}\,\sin\psi\;\theta$,
$\Delta p = \sqrt{\beta_1/\beta_2}\,\cos\psi\;\theta$. For $\psi = \pi/2$
the kick is a pure position offset at the IP, and per unit phase offset

$$
\frac{\delta x_{IP}}{\delta\phi} = \frac{\sqrt{\beta_{cc,x}\beta_x^*}\,|s_i|}{ik}
 = \frac{|w_i|\tan\theta_c}{ik}:
$$

the phase error moves the crabbing node by $\delta\phi/(ik)$ along the bunch
and the crabbing tilt turns that longitudinal shift into a transverse one.
Numbers (dipole part, $z = 0$; the bunch centroid sees
$\langle\cos ikz\rangle$ times these):

| $i$ | $\delta x_{IP}/\delta\phi$ | per 10 µrad | in $\sigma_x^*$ |
|---|---|---|---|
| 1 | $4.037\times10^{-3}$ m/rad | $4.04\times10^{-8}$ m | $4.25\times10^{-4}$ |
| 2 | $5.046\times10^{-4}$ m/rad | $5.05\times10^{-9}$ m | $5.3\times10^{-5}$ |

In the normalised units of section 4 the kick amplitude is
$a = \sqrt{\beta_{cc}/\varepsilon_x}\;\theta = \sqrt{\beta_{cc}\beta^*}\,\theta/\sigma_x^*$,
so $a = 4.25\times10^{-4}$ per 10 µrad on the fundamental, and including the
residual $\langle a^2\rangle = (4.25\times10^{-4})^2\times0.9422$.

### 2.3 The downstream cavity, and why its position does not matter

The second cavity sits a quarter wavelength after the IP. Its kick reaches
the next collision after the phase advance $2\pi Q_x - \pi/2$, so on the
first passage the offset is $-\sqrt{\beta_{cc}\beta^*}\cos(2\pi Q_x)\,\theta
= -0.138\sqrt{\beta_{cc}\beta^*}\,\theta$, and thereafter it is a free
betatron oscillation of normalised amplitude $\sqrt{\beta_{cc}}\,|\theta|$,
the same as the upstream cavity's.

*Lemma (uncorrelated kicks add in quadrature wherever they act).* In
normalised coordinates $(X,P) = (x/\sqrt\beta,\ (\alpha x+\beta p)/\sqrt\beta)$
one turn is the rotation $R(2\pi Q)$, transport from the kick point to the
IP is a rotation $R(\psi)$, and a kick $\theta_n$ adds the vector
$v_n = \sqrt{\beta_k}\,\theta_n\,\hat e_P$ at its point. The ring being
linear, after $T$ turns the IP vector is
$\sum_n R\bigl(2\pi Q(T-n)\bigr)R(\psi)\,v_n$. Its expected squared length is
$\sum_n|v_n|^2 + \sum_{n\ne m}\langle v_n\!\cdot\!R(\cdot)v_m\rangle
= \sum_n\beta_k\langle\theta_n^2\rangle$, because rotations preserve length
and $\langle\theta_n\theta_m\rangle = 0$ for $n\ne m$ kills every cross
term whatever the angles. So $\langle J\rangle$ grows by
$\beta_k\sigma_\theta^2/2$ per kick regardless of $\psi$ and $Q$: for an
uncorrelated sequence only the normalised amplitude counts, and the
downstream cavity (same $\beta_{cc}$, same $s_i$, its own stream) contributes
exactly as much as the upstream one. For correlated sequences the cross
terms survive and the angles re-enter through the spectrum at the betatron
tune (section 5). The lemma needs the kicks to be independent of the
particle's own coordinates, which external noise is.

### 2.4 The common-timing alternative

If both harmonics ride one timing reference, $\delta\phi_i = i\,\delta\phi_1$
and the dipole errors add coherently:

$$
\frac{\delta x_{IP}}{\delta\phi_1} = \sqrt{\beta_{cc}\beta^*}\,
\frac{s_1\langle\cos kz\rangle + s_2\langle\cos 2kz\rangle}{k}
 = 3.02\times10^{-3}\ \text{m/rad},
$$

against the independent-stream quadrature sum
$\sqrt{\beta_{cc}\beta^*}\bigl[(s_1\langle\cos kz\rangle/k)^2 +
(s_2\langle\cos 2kz\rangle/2k)^2\bigr]^{1/2} = 3.94\times10^{-3}$ m/rad: the
growth rate under common timing is 0.588 times the independent-stream rate.

## 3. The kick error from an amplitude offset

### 3.1 Crabbing-angle error and its rms over the bunch

The kick is linear in the strength, so exactly

$$
\Delta p_x^{(i)}(\delta s) - \Delta p_x^{(i)}(0) = -\frac{\delta s}{ik}\sin(ikz)
 = -\delta s\, z\Bigl[1 - \frac{(ikz)^2}{6} + \dots\Bigr].
$$

Its $z$-slope at the bunch centre is $-\delta s$: the crabbing angle at the
IP is wrong by $\sqrt{\beta_{cc}\beta^*}\,\delta s = |w_i|\tan\theta_c\,
(\delta s/|s_i|)$, i.e. 1.67 µrad on the fundamental for $\sigma_A =
10^{-4}$ (0.42 µrad on harmonic 2). The kick is odd in $z$: it has zero mean
over the bunch and does not move the centroid; it is a $z$-correlated dipole
kick whose rms is $\delta s\,\langle\sin^2 ikz\rangle^{1/2}/(ik)$ with

$$
\langle\sin^2 ikz\rangle = \tfrac12\bigl(1-e^{-2(ik\sigma_z)^2}\bigr)
 = 0.0578\ (i=1),\quad 0.1940\ (i=2)
$$

(small-argument values $(ik\sigma_z)^2 = 0.0614$, $0.2455$). In normalised
units, with $\delta s = \sigma_A|s_i|$ at $\sigma_A = 10^{-4}$ (the relative
factor $d$ of rms $\sigma_A$ acting on $s_i$, section 3.2; $a_y = 0$ for the
example's horizontal cavities):

| $i$ | $\delta s$ [m⁻¹] | rms kick [rad] | $a_x$ |
|---|---|---|---|
| 1 | $5.168\times10^{-8}$ | $3.01\times10^{-9}$ | $1.021\times10^{-3}$ |
| 2 | $1.292\times10^{-8}$ | $6.89\times10^{-10}$ | $2.34\times10^{-4}$ |

Compared with section 2 at the production point, the amplitude noise's rms
normalised kick is 2.5 times the phase noise's and its growth rate (which
goes as the square) 6.4 times. Being $z$-dependent, it grows the central
emittance directly, with no decoherence needed (section 4.2).

### 3.2 The vertical plane

The strength rule's offset is a relative factor: `realize` scales both
planes' strengths of the harmonic by the same $1 + d$, so the absolute
errors are $\delta s_X = s_i d$ and $\delta s_Y = s_{y,i} d$ (owner decision
2026-10-15, one voltage driver per cavity: design note section 10 and
`../design/turn_modulation_record.md`, section 5). The horizontal
crabbing-angle error of 3.1 is unchanged by the convention, $\delta s = s_i d$
being the same number as before for the same relative rms. The example's
cavities have `strengthY = 0`, so their vertical kick error is $s_{y,i} d =
0$: a horizontal cavity's amplitude noise excites no vertical emittance
growth of its own, and whatever vertical growth the colliding runs show is
the beam-beam coupling of 4.5 alone. Without the strong beam, vertical
emittance growth under horizontal amplitude noise falsifies the
implementation (section 7). A cavity with both strengths set receives the
error in both planes in proportion to its strengths: with $\beta_{cc,y} =
100$ m, $\beta_y^* = 0.072$ m, $\sigma_y^* = 8.5$ µm,
$a_y/a_x = (s_{y,i}/s_i)\,\sqrt{\beta_{cc,y}\beta_y^*}\,\sigma_x^*/
(\sqrt{\beta_{cc,x}\beta_x^*}\,\sigma_y^*) = 0.93\,s_{y,i}/s_i$, and the
vertical telescope's zero phase advance delivers the kick to the IP as an
angle rather than an offset, which by the lemma of section 2.3 leaves the
growth rate unchanged.

Superseded model (the semantics shipped 2026-10-12 to 2026-10-15 as the
default taken in the owner's absence, and the one the 2026-10-14 record
measured): one absolute offset $\delta s$ added to both `strengthX[i]` and
`strengthY[i]` gave a horizontal cavity a vertical crabbing error of the
same absolute slope, $a_y = \sqrt{\beta_{cc,y}\beta_y^*}\,\delta s\,
\langle\sin^2 ikz\rangle^{1/2}/(ik\,\sigma_y^*) = 0.93\,a_x$
($9.50\times10^{-4}$ and $2.18\times10^{-4}$ on harmonics 1 and 2), hence a
vertical rate 0.865 of the horizontal under amplitude noise, measured 1.16
with the beam-beam coupling included.

## 4. Emittance growth of the weak beam

### 4.1 Random dipole kicks

With $J = (X^2+P^2)/2$ at the kick point, a kick $\theta$ gives
$\Delta P = \sqrt{\beta_k}\,\theta$ and
$\Delta J = P\,\Delta P + \Delta P^2/2$. Averaging over the beam and the
noise, $\langle P\theta\rangle = \langle P\rangle\langle\theta\rangle = 0$
because the kick is independent of the particle's coordinates, so
$\langle\Delta J\rangle = \beta_k\langle\theta^2\rangle/2$. Writing the kick
in units of the beam's normalised size, $a \equiv \sqrt{\beta_k/\varepsilon}\;\theta$
(equal to $\theta/\sigma_{x'}$ at a point where $\alpha = 0$, as at both
cavities),

$$
\frac{d\langle J\rangle}{dn} = \frac{\varepsilon}{2}\,\langle a^2\rangle
\quad\text{per kick and turn},
$$

where $\langle a^2\rangle$ includes the bunch average over $z$ for
$z$-dependent kicks. For an IP offset $d$ in units of $\sigma_x^*$ produced
by the upstream cavity, $a = d$ (a pure position offset of $d\sigma^*$ is
the normalised vector $d\sqrt{\varepsilon}\,\hat e_X$), so
$d\langle J\rangle/dn = \varepsilon d^2/2$.

### 4.2 Raw and central emittance; decoherence

The rms emittance $\varepsilon_{\rm raw} = \sqrt{\langle x^2\rangle\langle p^2\rangle
- \langle xp\rangle^2}$ with moments about the design orbit equals
$\langle J\rangle$ for a phase-mixed distribution. With a displaced centroid
of action $J_c = (X_c^2+P_c^2)/2$ and central emittance $\varepsilon_c$,
$\langle J\rangle = \varepsilon_c + J_c$ and $\varepsilon_{\rm raw} =
\sqrt{\varepsilon_c^2 + 2\varepsilon_c J_c} \simeq \varepsilon_c + J_c$,
identical to first order in $J_c/\varepsilon_c$: the difference is
$J_c^2/(2\varepsilon_c)$, and $J_c$ stays below a few per cent of
$\varepsilon_c$ in every planned run (bounded by decoherence with the strong
beam on; the 1.7 % total growth in the linear control), so the two differ by
under 0.1 %. Section 4.1 predicts the growth of $\langle J\rangle$.

A dipole kick moves every particle equally. In a linear lattice
$\varepsilon_c$ is exactly conserved and all of $d\langle J\rangle/dn$ feeds
$J_c$: a centroid random walk, not an emittance growth. A tune spread
decoheres the centroid: each particle accumulates its own phase from the
same kick sequence, $J_c$ stays bounded at $O(\tau_d\,d\langle J\rangle/dn)$
and the growth continues in $\varepsilon_c$ at the full rate after the
decoherence time $\tau_d \approx 1/(2\pi\,\Delta Q_{\rm rms})$. Here the
spread is the beam–beam lens's, $\Delta Q$ from about 0 to $\xi_x$ with mean
$\xi_x/2$ (section 4.3), so $\tau_d$ is of order 50 to 300 turns. The
chromaticity with synchrotron motion gives only a reversible modulation: the
centroid amplitude factor $\exp[-2(\xi'\sigma_\delta/Q_s)^2\sin^2(\pi Q_s n)]$
dips to 0.966, so at most 7 % of $J_c$ appears transiently in
$\varepsilon_c$ and returns every synchrotron period. $z$-dependent kicks
(the amplitude noise, the residual of the phase noise) give different
particles different kicks and land in $\varepsilon_c$ directly.

### 4.3 The beam–beam-mediated response to an IP offset

The strong beam's kick as coded is $F_x = k_{bb}K_x(x,y;\sigma_x^*,\sigma_y^*)$
with $k_{bb} = -N_s r_p/\gamma = -9.008\times10^{-10}$ m (the example's
`kbb`, charges of opposite sign) and the Bassetti–Erskine response $K_x$
whose small-amplitude slope is $2/(\sigma_x^*(\sigma_x^*+\sigma_y^*))$: the
compiled kernel's slope, $-0.18323$ m⁻¹, agrees with
$2k_{bb}/(\sigma_x^*(\sigma_x^*+\sigma_y^*))$ to $10^{-6}$, so the
$(1+\beta)=2$ head-on convention is in the kernel. Hence

$$
\xi_x \equiv -\frac{\beta_x^* F_x'(0)}{4\pi}
 = \frac{N_s r_p\,\beta_x^*}{2\pi\gamma\,\sigma_x^*(\sigma_x^*+\sigma_y^*)} = 0.01166,
\qquad \xi_y = 0.01173 .
$$

*First-passage estimate (the owner's form).* A core particle offset by $d$
(in $\sigma_x^*$) relative to the strong beam receives the extra kick
$F_x'(0)\,d\sigma_x^* = -4\pi\xi_x\,d\,\sigma_x^*/\beta_x^*$, i.e. the
normalised amplitude $a_{bb} = 4\pi\xi_x d$ (with
$\sigma_{p}^* = \sigma_x^*/\beta_x^*$), so by 4.1

$$
\frac{d\langle J\rangle}{dn}\Big|_{bb} = \frac{\varepsilon}{2}(4\pi\xi_x)^2 d^2 .
$$

For the upstream cavity the offset is pure position and the beam–beam
response pure angle, orthogonal in $(X,P)$, so the two add in quadrature:
$\varepsilon d^2[1 + (4\pi\xi_x)^2]/2$ with $(4\pi\xi_x)^2 = 0.0215$.

*Self-consistent linear treatment.* The lens acts every turn, not only on
the turn of the kick; its persistent effect is to make the lattice the
perturbed one (tune shift, dynamic beta), in whose normalised coordinates
the lemma applies with $\beta_{cc}'$. For a thin lens of
$\beta^*K = 4\pi\xi$ at the IP, $\cos\mu' = \cos\mu - 2\pi\xi\sin\mu$,
$\beta^{*\prime}\sin\mu' = \beta^*\sin\mu$, and to first order
$\Delta\beta/\beta = -(2\pi\xi/\sin\mu)\cos(2\psi-\mu)$ at phase $\psi$ from
the lens: $Q_x' = 0.2396$, $\beta_x^{*\prime}/\beta_x^* = 0.9926$,
$\Delta\beta_{cc,x}/\beta_{cc,x} = +1.0\,\%$ ($\psi = \pi/2$); $Q_y' =
0.2216$, $\beta_y^{*\prime}/\beta_y^* = 0.984$,
$\Delta\beta_{cc,y}/\beta_{cc,y} \approx -2\,\%$ ($\psi = 0$). Either way
the beam–beam correction to the raw growth rate is 1 to 2 %, below the
resolution of section 7.

*Nonlinear force.* Over the Gaussian weak beam of the same sizes,
$\langle F_x'\rangle/F_x'(0) = 1/2$ exactly (for the round case, integrating
by parts, $\langle\partial_xF_x\rangle = \langle F_x x\rangle/\sigma^2 =
F'(0)\,\langle 1 - e^{-r^2/2\sigma^2}\rangle = F'(0)/2$, since the angular
average of $x^2/r^2$ is $1/2$ and $\langle e^{-r^2/2\sigma^2}\rangle = 1/2$
for a two-dimensional Gaussian; the elliptic code kick integrates to
0.5000), and
$\mathrm{rms}(F_x')/|F_x'(0)| = 0.645$ (elliptic, code kick; 0.597 for a
round beam of $\sigma_x^*$). The beam-averaged first-passage term is thus
$(4\pi\xi_x)^2\times0.645^2 = 0.009$; the real role of the $F'$ spread is
the tune spread that sets $\tau_d$ in 4.2.

### 4.4 Direct versus beam–beam-mediated, and the control run

The direct contribution, the cavity kick itself, is the whole raw growth
rate to within 1–2 %; the beam–beam changes the raw rate by 1–2 %; what the
beam–beam decides is whether the growth is a centroid random walk or a
central-emittance growth. A run with the strong beam's charge set to zero
(`kbb = 0`, `klum` kept so the luminosity channel still runs) separates the
two: under phase noise the centroid walks and $\varepsilon_c$ stays flat to
within the residual's share, $(\langle\cos^2\rangle-\langle\cos\rangle^2)/
\langle\cos^2\rangle = 0.18\,\%$ of the rate on the fundamental plus
2.9 % of harmonic 2's 1.3 %, about 0.2 % in all; under amplitude noise
$\varepsilon_c$ grows at the full rate with no centroid motion. With the
strong beam on, both rules grow $\varepsilon_c$ at the raw rate after
$\tau_d$. Section 7 builds the control into the sweep.

### 4.5 The vertical response through the beam–beam force (measured; derivation open)

The treatment above carries no vertical response to horizontal offset
noise: the offset $d$ enters $F_x$ only. The validation sweep (the record,
section 5) measured one with the beam–beam kick on: under purely horizontal
phase noise the vertical rate is 0.205 of the horizontal at the production
point (0.128 at scale 2, 0.072 at scale 4, 0.389 for the pink drive), and it
vanishes without the strong beam (the `kbb = 0` control grows nothing
vertically beyond its baseline). The mechanism is the $x$-dependence of the
flat strong beam's vertical force: an offset $d\,\sigma_x^*$ changes the
vertical kick on a particle at $(x, y)$ by $\partial_x F_y(x, y)\,d\,\sigma_x^*$
to first order, a stochastic vertical kick that grows $\varepsilon_y$ by the
random-kick formula of 4.1. Under the superseded additive strength
semantics the same term lifted the amplitude runs' vertical rate above the
both-planes prediction (scale 1: measured $1.180\times10^{-6}$ against
$9.5\times10^{-7}$ per turn, the 2026-10-14 record); under the relative
semantics of 3.2 the amplitude runs' vertical rate is this coupling alone,
which the re-validation of 2026-10-15 measured (the relative-strength
record, section 3): $y/x = 0.296$, $0.187$ and $0.085$ at scales 0.5, 1
and 2 (A05, A1, A2), 0.97, 0.84 and 0.63 of the excesses the 2026-10-14
record had attributed to the coupling, falling with the scale like the
phase arms' ratios above; 0.247 for the pink drive (AP1/A1 in $y$); and
the `kbb = 0` control's vertical emittance identical to the no-noise
baseline, so the falsifier of 3.2 did not fire. The ratio
$R = (d\langle J_y\rangle/dn)/(d\langle J_x\rangle/dn)$ for white horizontal
offset noise, $\langle(\partial_x F_y)^2\rangle\,\beta_y^*/\varepsilon_y$ over the
weak-beam distribution against the horizontal response of 4.3, is not
derived here (an owner row in `docs/todo.md`); its dependence on the noise
amplitude and on the spectrum, both measured, is unexplained until it is.

## 5. Coloured noise

### 5.1 The spectral form of the growth rate

Let $a_n$ be a real stationary sequence with autocovariance
$R(\tau) = \langle a_n a_{n+\tau}\rangle$ and two-sided power spectral
density $S(\nu) = \sum_\tau R(\tau)e^{-2\pi i\nu\tau}$, $\nu$ in units of
$f_{\rm rev}$ on $[-1/2,1/2]$, normalised so that $\int S\,d\nu = R(0) =
\sigma_a^2$. The IP vector of section 2.3 in complex form is
$\zeta_T = \sum_n a_n e^{2\pi iQ(T-n)}$ (a common rotation from $\psi$
dropped), and

$$
\mathbb E|\zeta_T|^2 = \sum_{n,m}R(n-m)\,e^{2\pi iQ(m-n)} \;\to\; T\,S(Q)
\quad (T \gg \text{correlation length}),
$$

so

$$
\frac{d\langle J\rangle}{dn} = \frac{\varepsilon}{2}\,S_a(Q),\qquad
S_a(Q) = S_a(-Q) = S_a(1-Q),
$$

which reproduces 4.1 for white noise ($S_a = \sigma_a^2$). With the DFT
periodogram $P(\nu_j) = |\sum_n a_n e^{-2\pi i\nu_j n}|^2/T$ on
$\nu_j = j/T$, whose mean over bins is $\sigma_a^2$, the same statement is
$d\langle J\rangle/dn = \varepsilon\,[P(Q)+P(1-Q)]/4$. For a cyclostationary
sequence (the pink rule) $R$ is the time-averaged autocovariance, and when
the window $T$ is a multiple of every block length the formula is exact
rather than asymptotic.

For one realisation the growth over $T$ turns is exactly
$\varepsilon\,T\hat P(Q)/2$ with $\hat P(Q) = |\sum_n a_n e^{2\pi iQn}|^2/T$
the realised periodogram at the betatron tune, an exponential variate of
relative sd 1 for Gaussian noise. A beam with tune spread averages it over
about $T\,\Delta Q_{\rm eff}$ independent bins; with
$\Delta Q_{\rm eff} \approx 0.35\,\xi_x$ the relative sd is about 5 % at
$T = 10^5$ turns and 11 % at $T = 2\times10^4$, and 100 % in a linear
lattice. This, not the macro-particle count, is the statistical floor of a
single-realisation rate measurement; the exact remedy is the
realisation-aware prediction of section 7.

### 5.2 The Voss–McCartney spectrum

Generator $k$ ($k = 0..K-1$, $K = 16$) holds a unit normal for $2^k$ turns
on blocks aligned to multiples of $2^k$ (keyed on `turn >> k`); the sum over
$\sqrt K$ has ensemble variance exactly $\sigma^2$ at every turn. A block
process of length $L$ has the time-averaged autocovariance
$R_L(\tau) = 1 - |\tau|/L$ for $|\tau| < L$ (the probability that turns $n$
and $n+\tau$ share a block) and zero beyond, whose transform is the Fejér
kernel $S_L(\nu) = \frac1L\bigl|\sum_{m=0}^{L-1}e^{-2\pi i\nu m}\bigr|^2
= \sin^2(\pi\nu L)/(L\sin^2\pi\nu)$. Independent generators add in power:

$$
\rho(\nu) \equiv \frac{S_{\rm pink}(\nu)}{\sigma^2}
 = \frac1K\sum_{k=0}^{K-1}\frac{\sin^2(\pi\nu\,2^k)}{2^k\sin^2(\pi\nu)} ,
$$

the pink-to-white PSD ratio at equal variance. Values: $\rho(0.228) =
0.1547$, $\rho(0.210) = 0.1800$, $\rho(0.240) = 0.1384$; means over the
incoherent tune bands $[Q, Q+\xi]$: 0.146 ($x$), 0.169 ($y$); weighting by
the tune density (mean shift $\xi/2$) gives $\bar\rho_x \approx 0.15$,
$\bar\rho_y \approx 0.17$, each $\pm0.01$. An ideal $1/f$ spectrum over 16
octaves would give 0.198 at 0.228: the construction's ripple (design note,
5.5) leaves about 20 % less power at the betatron tune. Numerical
confirmation (2000 realisations of $2^{16}$ turns of the exact construction
with `randn` as the keyed draw; `pink_mc.jl` in the campaign's numerics):
$\mathbb E|\sum a_n e^{2\pi iQn}|^2/T = 0.1560\pm0.0035$ at $Q = 0.228$,
$0.1817\pm0.0041$ at 0.210, $0.1429\pm0.0032$ at 0.240; the band-averaged
periodogram over $\sigma^2$ is 0.1541, 0.1799, 0.1383 against the analytic
0.1547, 0.1800, 0.1384. The sample variance of a $2^{16}$-turn record
averages $0.936\,\sigma^2$ (the sample mean absorbs the slowest generators),
so normalising a measured spectrum by the record's sample variance inflates
$\rho$ by 7 % (0.165 at 0.228): normalise by the rule's $\sigma$, the
ensemble rms. For the amplitude noise the $\sin(ikz)$ modulation samples the
synchrotron sidebands $Q\pm Q_s$, where $\rho = 0.164$ and $0.141$: the same
$\bar\rho$ within the quoted band.

**Finite-window statistics.** Over $N$ turns generator $k$ holds $N/2^k$
independent values, so the slowest generators enter a record's sample
variance as $\chi^2$ variates with few degrees of freedom (at $N = 2^{16}$:
four values for $k = 14$, two for $k = 15$) and give it a heavy upper tail.
The validation's Monte Carlo of the construction (8192 streams, $N =
2^{16}$) gives rms/$\sigma$ a standard deviation of 0.0737, a 99.9 %
quantile of 1.324 and $P(\mathrm{rms}/\sigma \ge 1.3425) = 0.085\,\%$ per
slot; one of the eight slots measured 1.3425 (its $k = 14$ generator drew
+1.44, −2.81, +0.45, +1.88) and converges to 1.188, 1.080, 1.030, 0.995 at
$2^{17}$ to $2^{20}$ turns. A $\pm3\sigma$ Gaussian band is the wrong shape
at $2^{16}$. The verification window is therefore $2^{20}$ turns, where the
Monte Carlo (4096 streams) gives a standard deviation of 0.0194 (the
variance formula 0.0191) and a two-sided 99 % band $[0.9545, 1.0594]$ for
rms/$\sigma$.

### 5.3 Consequences for the three rules at equal rms

White gives the full rate of section 4. Pink gives $\bar\rho$ times it,
about one sixth in $x$ and $0.17$ in $y$. The table rule reproduces whatever
spectrum the record has: a white synthetic record reproduces the white rate
within the realisation scatter of 5.1, and a table holding exactly the
realised white draws reproduces `WhiteNoise` to the bit, because both paths
add the same number to `phase[i]`.

## 6. Production-point numbers

$f_{\rm rev} = \beta c/C = 78\,196.75$ Hz, $2.815\times10^8$ turns per hour.
Rates are $d\langle J\rangle/dn$ relative to $\varepsilon$ of the plane,
summed over both cavities and both active harmonics with independent
streams; a scale factor $s$ on the rms multiplies every rate by $s^2$ (the
small-offset regime holds to $s \sim 100$).

| noise | rule | plane | per turn | per hour | doubling time |
|---|---|---|---|---|---|
| phase, $\sigma_\phi = 10$ µrad | white | $x$ | $1.72\times10^{-7}$ | 48.5 | 51 s |
| | pink ($\bar\rho_x = 0.15$) | $x$ | $2.5\times10^{-8}$ | 7.1 | 350 s |
| | table, white record | $x$ | as white | | |
| | any | $y$ | 0 | | |
| amplitude, $\sigma_A = 10^{-4}$ (relative) | white | $x$ | $1.10\times10^{-6}$ | 309 | 8 s |
| | white | $y$ | 0 without the strong beam; the coupling of 4.5 only with it | | |
| | pink ($\bar\rho_x$) | $x$ | $1.6\times10^{-7}$ | 45 | 55 s |
| | pink | $y$ | 0 without the strong beam; the coupling only with it | | |
| phase, common-timing alternative | white | $x$ | $1.01\times10^{-7}$ | 28.5 | 87 s |

The amplitude rows' vertical entries read $9.5\times10^{-7}$ (white) and
$1.6\times10^{-7}$ (pink) per turn under the superseded additive semantics of
3.2; those are the numbers the 2026-10-14 record measured against.

Harmonic 2 carries 1.3 % of the phase-noise rate and 5 % of the
amplitude-noise rate. The central values carry the exact bunch averages, a
1–2 % dynamic-beta correction and, for pink, a $\pm7\,\%$ tune-band
weighting; the predictions are believed good to 10 % (white) and 15 %
(pink). At factor level: a measured rate outside $[1/1.3,\ 1.3]$ times the
prediction is a defect, not a model correction.

On the size of these numbers: a per-turn white sequence of rms $\sigma_\phi$
has the one-sided PSD $2\sigma_\phi^2/f_{\rm rev} = 2.6\times10^{-15}$
rad²/Hz, flat to $f_{\rm rev}/2 = 39$ kHz, so the production point is a very
noisy LLRF (the emittance doubles in a minute). By the $s^2$ law the
1 %-per-hour point is $\sigma_\phi = 0.14$ µrad of per-turn-equivalent
white phase noise, or $\sigma_A = 5.7\times10^{-7}$. 

## 7. Verification: what `validation/crab_cavity_noise_response.jl` measures

The script is the campaign's deliverable; this section is its plan, written
in the present tense. The numbers it produces are recorded in the campaign's
history record under `docs/history/`, together with the recorded run
configuration (seeds, `rng_id`s, turns, device, per-turn cost); this note
carries only the predictions. The detailed plan is kept with the campaign
record (`plan.md`).

**Estimators.** The moment observer at the line end (IP optics, $\alpha = 0$)
records per turn the means `m100000`, `m010000` and the central second
moments `m200000`, `m110000`, `m020000` (vertical: `m001000`, `m000100`,
`m002000`, `m001100`, `m000200`). From them

$$
\bar J_{\rm raw}(n) = \tfrac12\Bigl[\tfrac{\texttt{m200000}+\texttt{m100000}^2}{\beta_x^*}
 + \beta_x^*\bigl(\texttt{m020000}+\texttt{m010000}^2\bigr)\Bigr],\quad
\varepsilon_c(n) = \sqrt{\texttt{m200000}\,\texttt{m020000}-\texttt{m110000}^2},\quad
J_c(n) = \tfrac12\Bigl[\tfrac{\texttt{m100000}^2}{\beta_x^*}+\beta_x^*\texttt{m010000}^2\Bigr],
$$

so that $\bar J_{\rm raw} = \varepsilon_c + J_c$ for an upright matched
distribution. $\bar J_{\rm raw}$ is what sections 4 and 5 predict;
$\varepsilon_c$ is the physical emittance; $J_c$ is the centroid's action.
The growth rate is the slope of a linear least-squares fit of
$\bar J_{\rm raw}(n)$ and of $\varepsilon_c(n)$ over $[n_0, T]$ with
$n_0 = 2000$ turns (past the decoherence time and the mismatch transient),
after subtracting the no-noise baseline run with the same seed, divided by
$\varepsilon$ of the plane.

**Statistics.** The sampling noise of one moment sample is
$\sqrt{2/N}$ relative ($1.4\times10^{-3}$ at $N = 10^6$, $3.2\times10^{-3}$
at $2\times10^5$), but it is almost fully correlated across turns: the
sample emittance is an exact invariant of the linear map, so turn-to-turn
jitter comes only from the nonlinear filamentation, which the baseline
measures. The floor of a single-realisation rate is the realised spectrum
(section 5.1): about 5 % at $T = 10^5$ with the strong beam on, 100 % with
it off. The sharp test for the linear control is therefore the
realisation-aware prediction: the realised offsets are a pure function of
(seed, `rng_id`, turn), so the centroid's trajectory follows from the kick
sequence through the linear maps with no statistical error.

**Sizing.** The growth at scale $s$ over $T$ turns is $R\,s^2 T$: at
$T = 10^5$ and $s = 1$ it is 1.7 % (phase white) and 11 % (amplitude white),
10 to 80 times the sampling floor at $N = 10^6$ and 5 to 35 times it at
$N = 2\times10^5$. $T = 10^5$ is also what the 5 % spectral floor needs;
pink runs use $T = 2^{17} = 131\,072$, a multiple of the longest block, so
that 5.2 is exact. One NVIDIA RTX 4500 Ada holds $10^6$ particles in 48 MB.
With $c$ ms per turn, fourteen runs of $1.1\times10^5$ turns on average cost
$1.5\times10^6\,c$ ms: 0.4 h at 1 ms, 2.1 h at 5 ms (the default,
$N = 10^6$), 4.2 h at 10 ms, plus one or two minutes of setup per run. The
6 h budget bounds $c \le 13$ ms/turn; beyond that use $N = 2\times10^5$. The
artifact is written to local disk (the per-turn write on a networked
filesystem dominates, as the example's output block records).

**Sweep.** Phase rules act on harmonics 1 and 2 of both cavities with
distinct `rng_id`s per cavity (also distinct from the beam's 1 and the
radiation's 2); strength rules likewise with the relative
$\sigma = s\cdot10^{-4}$ handed over directly (the factor on both planes'
strengths; before 2026-10-15 the absolute $s\cdot10^{-4}|s_i|$).

| run | rule | $s$ | `kbb` | $\xi'$ | turns | purpose |
|---|---|---|---|---|---|---|
| B0 | none | – | on | 2/2 | $10^5$ | baseline: drift floor of $\bar J_{\rm raw}$, $\varepsilon_c$; mismatch transient |
| W1 W2 W3 | phase `WhiteNoise` | 1, 2, 4 | on | 2/2 | $10^5$ | rate vs $1.72\times10^{-7}s^2$; exponent; $\varepsilon_c$ follows $\bar J_{\rm raw}$; $J_c$ bounded |
| P1 | phase `PinkNoise`(16 octaves) | 1 | on | 2/2 | $2^{17}$ | pink/white ratio vs $\bar\rho_x$ |
| T1 | phase `TurnTable` = W1's realised offsets | 1 | on | 2/2 | $10^5$ | bitwise reproduction of W1 |
| T2 | phase `TurnTable` = independent seeded white record | 1 | on | 2/2 | $10^5$ | table reproduces the white rate |
| A1 A4 | strength `WhiteNoise` | 1, 4 | on | 2/2 | $10^5$ | $x$ rate; $y$ the coupling of 4.5 only; no centroid motion |
| AP1 | strength `PinkNoise` | 1 | on | 2/2 | $2^{17}$ | pink/white in $x$ ($y$ information) |
| AT1 | strength `TurnTable` = seeded white record of relative factors | 1 | on | 2/2 | $10^5$ | table reproduces white |
| C0 | none | – | 0 | 0/0 | $10^5$ | linear baseline |
| C1 | phase `WhiteNoise` | 1 | 0 | 0/0 | $10^5$ | direct term: centroid vs exact linear prediction; $\varepsilon_c$ flat |
| C2 | strength `WhiteNoise` | 1 | 0 | 0/0 | $10^5$ | direct term lands in $\varepsilon_c$ in $x$; $\varepsilon_{c,y}$ at the baseline; centroid flat |
| C3 (optional) | phase `WhiteNoise` | 1 | 0 | 2/2 | $10^5$ | reversible chromatic decoherence $\le 7\,\%$ of $J_c$ |

**Acceptance.**

1. Rates (baseline-subtracted $\bar J_{\rm raw}$ slope over $\varepsilon$)
   for W1, A1 ($x$), T2, AT1 within a factor 1.25 of section 6; the
   baseline slope below 5 % of the $s = 1$ prediction. A1's vertical rate
   is reported as the coupling of 4.5, not judged against a prediction.
2. The exponent of rate versus $s$ from W1–W3 (and A1, A4) equal to 2 within
   $\pm0.1$ (log–log fit).
3. P1/W1 and AP1/A1 rate ratios in $x$ equal to $\bar\rho_x = 0.15$ within
   $\pm25\,\%$ (accept $[0.11, 0.19]$); the vertical AP1/A1 ratio is
   information, its rates being the coupling's.
4. T1's moment columns equal W1's to $10^{-10}$ relative (bitwise is
   expected; the tolerance covers reduction order).
5. With the strong beam on, the $\varepsilon_c$ slope is at least 0.8 of the
   $\bar J_{\rm raw}$ slope and $J_c$ shows no secular growth (its mean over
   the second half of the run below 10 % of the total growth).
6. C1: the recorded centroid (`m100000`, `m010000`) matches the linear
   prediction from the realised offsets (both cavities, bunch factor
   $\langle\cos ikz\rangle$ from the sampled $z$) to 1 % of its rms
   excursion; the $\varepsilon_c$ slope is below 1 % of the predicted raw
   rate; $\bar J_{\rm raw} - \varepsilon_c = J_c$ turn by turn.
7. C2: the horizontal $\varepsilon_c$ growth follows the covariance
   propagation of the realised strength factors through the linear maps
   (the record's control part; a first-moment rate ratio carries a 100 %
   single-realisation floor without tune spread), the vertical
   $\varepsilon_c$ stays at the C0 baseline, and the centroid stays within
   its sampling noise.
8. Fit quality: slopes from the two halves of the window agree within twice
   the expected spectral scatter; residual rms below 5 % of the total growth.

**Falsifiers.** A rate not scaling as $s^2$ (the rule's $\sigma$ is not what
the kick sees); a pink rate equal to the white rate (the rule's spectrum is
ignored); a phase-noise rate off by $(4/3)^2$, by $1/\langle\cos^2 kz\rangle$,
or by 2 (weights, bunch factor, or one cavity silent); two cavities sharing a
stream (their kicks correlate and the rate departs from the independent
prediction by a factor of order $1\pm\cos(\cdot)$); T1 differing from W1
(the table and white paths add different numbers); vertical growth under
horizontal amplitude noise WITHOUT the strong beam (a horizontal cavity
kicking vertically: the relative strength semantics not as coded), or
vertical growth under phase noise without the strong beam (with the strong
beam on, 4.5 makes vertical growth under either noise expected, at the
coupling's fraction $R$ of the horizontal rate, measured 0.2 for phase noise
at the production point); a horizontal amplitude-noise rate that changes
with the convention (the absolute horizontal error $s_i d$ is the same
number for the same relative rms); a rate that depends on $N$ or on the
backend beyond tolerance.

## 8. Owner-facing ambiguities

1. **Per-harmonic independent streams versus common timing.** Adopted:
   independent, 10 µrad on each of the two active harmonics of each cavity.
   Common timing gives 0.59 of the rate (section 2.4).
2. **The both-planes strength semantics (decided 2026-10-15 by the owner:
   a relative factor on both planes).** As raised: a horizontal cavity with
   `strengthY = 0` acquired vertical crabbing noise of the same absolute
   slope, so the vertical emittance grew at 0.87 of the horizontal rate
   under amplitude noise, where a physical voltage error scales both planes
   proportionally and gives no vertical noise here. The owner's reasoning:
   one voltage driver excites a cavity's horizontal and vertical kick, so
   one relative amplitude error $d$ scales both, $S_X(1+d)$ and $S_Y(1+d)$;
   a second driver is a second cavity. The additive semantics, the
   2026-10-12 default taken in the owner's absence, made a horizontal
   cavity kick vertically (predicted 0.865 of the horizontal rate; the
   2026-10-14 record measured 1.16 including the beam-beam coupling).
   Under the relative semantics the horizontal physics is unchanged (the
   absolute horizontal kick error is $S_X d$, the same number as before for
   the same relative rms) and a horizontal cavity's vertical kick is zero;
   the falsifier is vertical emittance growth under horizontal amplitude
   noise without beam-beam. The RF cavity's voltage follows the same
   convention, $V(1+d)$. Implementation: stage 0 of
   `../design/turn_modulation_record.md`, landed 2026-10-15 as f7cfe6a,
   re-validated, gated and pushed as c070750 (CI run 454 green; the status
   brought current by the 2026-10-16 neighbour audit); record
   `../history/crab_cavity_noise_relative_strength_2026_10_15.md`.
3. **The production point is loud.** Doubling times of a minute (phase)
   and eight seconds (amplitude); fine as a test point, where $10^5$ turns
   (1.3 s of beam) give 2–11 % growth, but not an LLRF specification. The
   1 %/h-equivalent per-turn rms is 0.14 µrad / $5.7\times10^{-7}$.
4. **The beam–beam-mediated change of the raw rate is 1–2 %**, not
   measurable at the planned statistics; what the `kbb = 0` control shows is
   the decoherence (central versus raw emittance). If a larger
   beam–beam-mediated term was expected, this is where the model says no.
5. **Pink normalisation.** $\bar\rho$ is defined against the rule's
   ensemble $\sigma$; normalising by a record's sample variance inflates it
   by 7 %.

6. **The vertical response ratio $R$ is measured, not derived** (4.5):
   0.205 of the horizontal rate under phase noise at the production point,
   falling with the amplitude and larger for pink. Deriving it from
   $\partial_x F_y$ of the flat strong beam is the open theory item.

## References

1. V. A. Lebedev, V. V. Parkhomchuk, V. D. Shiltsev, and G. V. Stupakov,
   "Emittance growth due to noise and its suppression with the feedback
   system in large hadron colliders," *Particle Accelerators* **44** (1994)
   147–164 (SSCL-Preprint-188): emittance growth from dipole noise as the
   noise PSD at the betatron sidebands; the form used in section 5.1.
2. P. Baudrenghien and T. Mastoridis, "Transverse emittance growth due to rf
   noise in the high-luminosity LHC crab cavities," *Phys. Rev. ST Accel.
   Beams* **18**, 101001 (2015): crab-cavity phase and amplitude noise with
   the bunch factors $\langle\cos^2\rangle$ and $\langle\sin^2\rangle$ of
   sections 2 and 3, and the role of the transverse damper (absent here).
3. K. Ohmi *et al.*, "Response of colliding beam-beam system to harmonic
   excitation due to crab-cavity rf phase modulation," *Phys. Rev. ST Accel.
   Beams* **14**, 111003 (2011): the KEKB crab-cavity phase-modulation
   experiment and its beam–beam simulation.
4. R. E. Meller, A. W. Chao, J. M. Peterson, S. G. Peggs, and M. Furman,
   "Decoherence of kicked beams," SSC-N-360 (1987): the chromatic
   decoherence factor of section 4.2.
5. M. Bassetti and G. A. Erskine, "Closed expression for the electrical
   field of a two-dimensional Gaussian charge," CERN-ISR-TH/80-06 (1980):
   the kick of section 4.3.
6. A. W. Chao, K. H. Mess, M. Tigner, and F. Zimmermann (eds.), *Handbook of
   Accelerator Physics and Engineering*, 2nd ed., World Scientific (2013):
   beam–beam tune shift, dynamic beta, and emittance growth from noise.
7. EIC crab-cavity noise tolerance studies (BNL beam–beam group, weak–strong
   and strong–strong simulations with Lorentz-boosted crab crossing,
   2021–2023) report tolerances of the order section 6's scaling implies;
   cited by description only.
8. The Voss–McCartney construction and its measured spectra: the design
   note's references and section 5.5.
