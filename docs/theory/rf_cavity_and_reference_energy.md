# RF Cavities, and Whether There Is a Reference Particle

Octopus has no RF cavity. `thin_crab_cavity` is transverse only, so there is
nothing that closes the longitudinal plane — no synchrotron motion, no bucket,
no longitudinal Twiss. That blocks the optics work, which is why this note
comes first.

The question that has to be answered before any map is written is not about the
cavity. It is: **does Octopus need a reference particle?**

## 1. The answer: no reference *particle*, yes a reference *profile*

A reference particle must not be tracked, and the reason is circular rather
than practical. The coordinates are *defined against* the reference —
$p_x = P_x/P_0$, $p_z = \Delta P/P_0$. Track the reference and its own
integration error leaks into the definition of every other particle's
coordinates, and that definition starts depending on which tracking method was
selected. All four reference codes treat the reference as **bookkeeping**: Bmad
computes `p0c` per element in a bookkeeping pass, AT stores `Energy` as a field
*on the cavity element*, and nothing propagates a seventh particle.

What is genuinely needed, and only when a cavity accelerates, is a reference
**energy profile** $P_0(s)$: a design-time cumulative pass along the line.
That is structurally the same object as `s_positions` — one is the geometric
survey, the other the energy survey — and it belongs in the same place, on the
line, computed rather than stored.

## 2. What the four codes do

| | element(s) | reference energy | energy kick |
|---|---|---|---|
| **Bmad** | **two**: `rfcavity`, `lcavity` | constant / **changes** | $-qV\sin\!\big(2\pi(\phi_t-\phi_\text{ref})\big)$ / $qG L\cos\!\big(2\pi(\phi_t+\phi_\text{ref})\big)$ |
| **MAD-X** | one `RFCAVITY` | constant in practice | $\Delta E = V\sin\!\big(2\pi(\mathrm{LAG} - h f_0 t)\big)$ |
| **elegant** | one `RFCA` + `CHANGE_P0` flag | switchable | phase in degrees, `PHASE=90` is crest |
| **AT** | one `RFCavity` | constant; `Energy` is an element field | $\Delta\delta = -\frac{V}{E}\sin\!\big(2\pi f(ct-\text{lag})/c - \varphi_\text{lag}\big)$ |

Two structural choices are on offer. Bmad splits the accelerating case into a
**separate element type**; elegant keeps one element and adds a **flag**.

## 3. Bmad's split is not redundancy, and this is the key finding

It is tempting to read `rfcavity` versus `lcavity` as one element with a
boolean. It is not, because **the phase convention differs between them**:

- `rfcavity`: $\Delta E \propto -\sin(2\pi(\phi_t - \phi_\text{ref}))$, so
  $\phi_0 = 0$ gives **zero net acceleration** — the natural zero for a ring.
- `lcavity`: $\Delta E \propto \cos(2\pi(\phi_t + \phi_\text{ref}))$, and Bmad
  states plainly that $\phi_0 = 0$ **is on crest** — the natural zero for a
  linac.

Sine versus cosine, and the sign of the phase argument reversed. A single
element with a `change_p0` flag would therefore have a `phase` parameter whose
*meaning silently changes* when the flag is set. That is exactly the class of
trap this codebase has been paying down all along — `tilt` versus `ref_tilt`,
reflection versus reversal — and the same resolution applies: **two names for
two things.**

## 4. Four codes, four phase conventions

The single most likely source of a wrong answer, and worth stating before any
implementation:

- **MAD-X** `LAG` is in units of $2\pi$, and its `VOLT` is in **MV**, its
  `FREQ` in **MHz**.
- **Bmad** `phi0` is in rad/$2\pi$, and the manual gives the conversion
  outright: **`phi0 = mad_lag + 0.5`**. Half a turn, not zero.
- **AT** carries a `TimeLag` (a *length*, divided by $c$) *and* a separate
  `PhaseLag`.
- **elegant** `PHASE` is in **degrees**, with `PHASE=90` the crest and
  `PHASE=180` the stable phase for a storage ring above transition.

Any importer that maps one code's phase onto another's without the offset
produces a cavity that tracks, looks plausible, and sits on the wrong side of
the bucket.

**Octopus does not get to pick freely, because it already picked.**
`ThinCrabCavity` is an RF element that exists and is validated, and its
convention is the house one:

```julia
kcc = 2π * frequency / CLIGHT      # frequency in Hz
θ   = i * kcc * z + phase[i]       # phase in RADIANS, additive
```

- `frequency` in **Hz**, not MAD-X's MHz;
- `phase` in **radians**, not MAD-X's units of $2\pi$, not Bmad's rad/$2\pi$,
  not elegant's degrees;
- the argument is $k z + \varphi$, **additive**, taken against Octopus's own
  longitudinal coordinate rather than a time or a $ct$;
- harmonics are tuples, so a multi-harmonic cavity is native rather than an
  extension.

The accelerating cavity must match this, and the reason is stronger than tidiness:
a user who sets `phase` on a crab cavity and `phase` on an RF cavity in the same
lattice must not be writing two different quantities. Internal consistency beats
matching any one external code, and the conversions to all four belong in the
docstring so an importer has them in one place:

| from | to Octopus `phase` [rad] |
|---|---|
| MAD-X `LAG` [units of $2\pi$] | $2\pi\,\mathrm{LAG}$, plus the sine/cosine and sign reconciliation of §3 |
| Bmad `phi0` [rad/$2\pi$] | $2\pi\,\phi_0$, and recall $\phi_0 = \mathrm{LAG} + 0.5$ |
| elegant `PHASE` [deg] | $\pi\,\mathrm{PHASE}/180$ |
| AT `TimeLag` [m], `PhaseLag` | $-k\,\mathrm{TimeLag} - \varphi_\mathrm{lag}$ |

These conversions are stated from the definitions above and are **not yet
verified numerically**; the reference case of §8 is what would pin them.

## 5. What the map must respect in *our* convention

Octopus tracks $p_z = \Delta P/P_0$ under `TIME=false`, convention #3 of
[`lattice_hamiltonian_and_conventions.md`](lattice_hamiltonian_and_conventions.md)
§2. A cavity's natural kick is in **energy**, not momentum, so it does not drop
straight into $p_z$:

$$E^2 = (Pc)^2 + (mc^2)^2 \;\Longrightarrow\; \mathrm{d}E = \beta c\,\mathrm{d}P
\;\Longrightarrow\; \Delta p_z = \frac{\Delta E}{\beta c P_0}.$$

The $\beta$ factor is exactly what disappears in the ultrarelativistic limit and
exactly what a proton ring needs. **The implementation must derive this in the
code's own convention rather than copying a formula from a code that uses
another one** — AT's $\Delta\delta = -(V/E)\sin(\cdot)$ is written for AT's
$\delta$ and its $ct$, not ours. Getting it wrong is invisible on-crest and
wrong everywhere else.

The arrival phase likewise depends on the longitudinal variable's definition,
and ours is not AT's $ct$ nor MAD-X's $t$.

## 6. Proposed design

**Scope A — `RFCavitySpec`, constant reference energy. Do this now.**

It closes the longitudinal plane, gives synchrotron motion and the bucket,
unblocks Twiss, and needs no reference machinery whatsoever.

```
RFCavitySpec(; voltage, frequency | harmon, phase=0, L=0, e0)
```

- **Thick cavity by drift–kick–drift**, as AT does: half drift, longitudinal
  kick, half drift. `L = 0` is the thin limit and should be exact, not a
  special case bolted on.
- **The cavity does NOT carry a reference energy.** AT stores `Energy` on its
  cavity, but Octopus's own precedent is stronger and is the one to follow —
  see §6a. The spec takes a **normalized strength**, not a voltage plus an
  energy.
- **`harmon` needs the circumference**, since $f = h f_0$ and
  $f_0 = \beta_0 c / C$. The line knows $C$ — `total_length` already exists —
  which makes this the third real consumer of `BeamLine` after assemblies and
  aperture positions. Supplying `harmon` without a line to resolve it against
  must throw rather than guess.

### 6a. Why the cavity must not hold an energy

`BeamParams` already has an `E0`. If the cavity also held one, a lattice could
declare two different reference energies and nothing would notice. The codebase
has already met this problem and answered it, twice:

- **`ThinCrabCavity` takes `strengthX`/`strengthY`** — already-normalized kicks.
  It carries no energy at all, because a normalized strength does not need one.
- **The strong-beam `kbb` is derived from `E0` at setup**,
  `kbb = q_1 q_2 r_0 N \, mc^2 / E_0`, and may also be supplied directly. The
  energy is used to *compute a number* and is then out of the picture.

And the architecture enforces it: `execute!(task, beam::Beam)` calls
`execute!(task, beam.rep)`, **dropping the parameters entirely**. Tracking never
sees `E0`, so an element that stored one would be storing something the
tracking layer cannot corroborate.

> **Elements carry normalized strengths. `E0` is a beam property, used at setup
> to derive them, and never enters tracking.**

So the mismatch cannot occur, because there is only ever one number: the
element holds a ratio, not two quantities that could disagree. Following the
beam-beam ergonomics, a user may give the normalized strength directly, or
derive it from a beam with a helper — and the helper is the single place `E0`
is read, which is the place to validate it.

The cost is stated plainly: **a normalized cavity cannot self-consistently
accelerate**, because the normalization is what changes. That is not a gap in
this design, it is the boundary of Scope A. Scope B needs the $P_0(s)$ channel
regardless, and that channel is exactly what would renormalize.

**Scope B — an accelerating cavity. Defer, and follow Bmad.**

A separate element kind, not a flag, for the reason in §3. It needs:

1. $P_0(s)$ as a line-level pass, cached like `s_positions`;
2. a **coordinate rescaling** at every energy boundary,
   $p_x \to p_x P_{0,\text{old}}/P_{0,\text{new}}$ and likewise for $p_y, p_z$.
   This is not bookkeeping — it *is* adiabatic damping, and omitting it leaves
   every individual map correct while the emittance is wrong;
3. a channel for the line to tell an element its local $P_0$, which **does not
   exist today** and is the actual architectural addition;
4. an answer to what a transfer matrix means when the map is symplectic only
   *after* rescaling — which is precisely why Bmad carries `p0c` on every
   element rather than on the lattice.

## 7. The self-referential phase, which has to be decided not discovered

The RF phase depends on arrival time, which depends on path length, which in a
ring depends on the closed orbit, which depends on the RF. Codes cut this by
*defining* the reference as the particle that arrives at the design phase and
then iterating the closed orbit. Bmad additionally distinguishes **absolute**
from **relative** time tracking (manual §26.1) and has an autoscale pass
(`phi0_autoscale`, `field_autoscale`) whose entire job is to make the delivered
energy gain match what the user asked for.

Octopus should choose the simplest thing that is honest — relative time, phase
measured against the design arrival — and say so, rather than inheriting an
ambiguity.

## 8. How this gets validated

1. **The thin limit.** `L = 0` and the drift–kick–drift thick cavity at `L → 0`
   must agree to round-off.
2. **Zero voltage is the identity**, bit for bit, as `ref_tilt = 0` and
   `x_offset = 0` already are elsewhere.
3. **Symplecticity** by complex step, as every other element.
4. **The synchrotron tune** against the analytic
   $\nu_s = \sqrt{h\,\eta\,qV\cos\phi_s / (2\pi\beta^2 E)}$ for a simple ring —
   this is the check that the $\beta$ factor of §5 is right, and it is the one
   that a formula copied from another code's convention will fail.
5. **Against MAD-X/PTC**, through the existing `PTCConsistencyContract` route,
   which is what pins the phase convention rather than merely documenting it.

## 9. Open questions for the human

1. ~~Phase convention?~~ **Settled: follow `ThinCrabCavity`** — frequency in
   Hz, phase in radians, argument $kz + \varphi$ (§4). The codebase had already
   chosen, and two RF elements in one lattice must not mean two different things
   by `phase`.
2. ~~Does `RFCavitySpec` take `e0`?~~ **Settled: neither — it takes a
   normalized strength and no energy at all** (§6a). `BeamParams.E0` is the one
   source of truth, it is read only at setup to derive the strength, and
   tracking never sees it. Two energies could disagree; a ratio cannot.
3. Is a `harmon` that cannot be resolved without a line an error, or should the
   cavity simply require `frequency` until lines carry a circumference?
