# The Reference Ramp: a Quasi-Static Energy Program for a Ring

> **Status (2026-11-27): written first, implemented the same day** (record
> [`../history/machine_description_reference_ramp_2026_11_27.md`](../history/machine_description_reference_ramp_2026_11_27.md);
> `ReferenceRamp`, `synchronous_phase_program`, the four suite testsets
> "Reference ramp: ..." and `validation/reference_ramp.jl`). Where the
> implementation departs from the first text, the paragraph says
> "Implemented:" and states what landed.
> Batch C of
> [`../design/machine_description_followups.md`](../design/machine_description_followups.md)
> (ruling R7) and case 4 of the taxonomy in
> [`../design/survey_and_reference_channel.md`](../design/survey_and_reference_channel.md)
> section 6: a ramping ring's reference momentum is a per-turn scalar, time
> variation is a scheduled control action on a knob, the kernels never see
> time, and the turn boundary applies the re-referencing map of the energy
> survey to the live beam. This note derives that map in the code's own
> convention, states the quasi-static model's error, fixes what the ramp
> program is and what the RF must satisfy, names the validation targets
> that make the implementation a contract, and records the scope boundary
> and the owner's choices. Parent notes:
> [`rf_cavity_and_reference_energy.md`](rf_cavity_and_reference_energy.md)
> (the cavity in `TIME_ENERGY`, the accelerating cavity's re-referencing),
> [`arc_survey_and_velocity_slip.md`](arc_survey_and_velocity_slip.md) (the
> slip factor the ring closes with),
> [`lattice_hamiltonian_and_conventions.md`](lattice_hamiltonian_and_conventions.md)
> (convention #3), [`../knob_control.md`](../knob_control.md) (knobs,
> epochs, the recompile).

## 1. The model: a flat profile within the turn, a step at the boundary

A ring at reference momentum $P_0$ holds every element at a normalised
strength ($k = qB/P_0$, the cavity's $qV/(P_0 c)$, the strong beam's
$k_{bb} \propto 1/E_0$) and every particle at coordinates normalised to
$P_0$: convention #3 of the conventions note, $(x, p_x, y, p_y, z, \delta)$
with $p_x = P_x/P_0$, $\delta = \Delta P/P_0$. A synchrotron ramp changes
$P_0$ by a few parts in $10^6$ per turn (RHIC: $\sim 3\times10^{-6}$; a
booster: $\sim 10^{-4}$), and within one turn the reference is flat to that
same order, so the dynamic part of the reference is **one scalar per turn**,
$P_0(n)$. The quasi-static model is:

1. within turn $n$ every element is compiled against $P_0(n)$ and every
   coordinate is normalised to it; the ring cavity delivers its energy to
   the particles as a change of $\delta$ (through $p_t$, the theory note's
   §5), the reference itself not moving mid-turn;
2. at the boundary between turn $n$ and $n+1$ the reference steps to
   $P_0(n+1)$: the coordinates are re-referenced (section 2), the knob the
   reference depends on is assigned, the epoch moves, and every
   knob-dependent element recompiles against the new reference before turn
   $n+1$ tracks.

The error of the flat profile is the normalisation mismatch between a
particle that has already been kicked by the cavity and the elements after
the cavity in the same turn: relative $\Delta P_{\rm ref}/P_0$ per turn,
over a fraction of a turn -- $10^{-6}$ to $10^{-4}$ on the normalised
strengths for part of one turn, far below the $10^{-3}$ effects a ramp
study resolves. The design chose this on purpose (the survey note, section
6): the reference is bookkeeping, the per-turn update reproduces ramp
physics, and no kernel carries a clock.

## 2. The boundary map on a live beam

Let $\rho = P_0(n)/P_0(n+1)$ be the ratio of successive references (below
one while accelerating). A particle's physical momentum $P$, transverse
momenta $P_x, P_y$ and arrival time at the boundary are what they are; only
the bookkeeping changes. Normalised to the new reference:

$$
p_x' = \frac{P_x}{P_0'} = \rho\,p_x,\qquad
p_y' = \rho\,p_y,\qquad
1+\delta' = \frac{P}{P_0'} = \rho\,(1+\delta),\qquad
x' = x,\quad y' = y,\quad z' = z .
$$

That $z$ is unchanged is a statement about convention #3 at a point:
$z_3 = s(1 - \beta/\beta_0) - \beta c\,\Delta t$ (the conventions note,
§2.2 with the table's $q_t$), and at the boundary $s$ is fixed, $\Delta t$
is measured against the design particle's arrival, which defines the clock
on both sides (the relative-time choice of the RF note's §7), and $\beta$ is
the particle's own velocity, which re-referencing does not touch; the
$\beta_0$-dependent part of $z_3$ is the velocity slip, which enters per
element through the cavity's symplectic $z$-shift (the slip note, §3) and
is recompiled with the new $\beta_0$ by the knob route. The same map in the
`TIME_ENERGY` pair is $p_t' = \rho\,p_t - \Delta E_{\rm ref}/(P_0' c)$ with
$z_1$ unchanged -- the accelerating cavity's re-referencing with the kick
left out (`_acc_kick` in `src/elements/rf_cavity.jl`: subtract the design
gain, scale by $\rho$, convert back at the exit pair) -- and the two agree
exactly, since $1+\delta' = \sqrt{(E/P_0'c)^2 - (mc^2/P_0'c)^2} = P/P_0'$.
The convention-#3 form needs no square root and no pair, which is why the
implementation should use it: three multiplications per particle, bitwise
the same on every backend.

The Jacobian is $\mathrm{diag}(1, \rho, 1, \rho, 1, \rho)$: determinant
$\rho^3$, one factor per canonical pair, the same statement the accelerating
cavity pins (`det J = ρ³`). Each plane's rms emittance scales by $\rho$,
$\varepsilon_x' = \rho\,\varepsilon_x$, so along a ramp

$$
\varepsilon_x(n)\,P_0(n) = \varepsilon_x(n)\,m c\,\beta_0\gamma_0(n) = \text{const},
$$

**adiabatic damping** as the product of exact boundary scalings, holding to
roundoff on a linear ring (a symplectic map at fixed $P_0$ preserves the rms
emittance of a sample exactly in exact arithmetic). It is not an
approximation the implementation makes; it is what re-referencing means,
and omitting it leaves every map correct and the emittance wrong (the RF
note's §6, item 2).

The synchronous particle. During turn $n$ the ring cavity gives a particle
at $z_1$ the energy $qV\sin(k z_1 + \varphi)$ (the cavity body
`pt += strength * sin(k*z1 + phase)`, `strength = qV/(P_0 c)`). The
particle at $z_1 = 0$ gains $\Delta E_s = qV\sin\varphi$, i.e.
$\delta_s = \Delta P_s/P_0$ with $\Delta E = \beta c\,\Delta P$ to first
order, and after the boundary $1 + \delta_s' = \rho\,(1+\delta_s) =
(P_0 + \Delta P_s)/P_0'$. It stays the reference particle, $\delta_s' = 0$,
exactly when

$$
P_0(n+1) - P_0(n) = \Delta P_s \iff E_0(n+1) - E_0(n) = qV\sin\varphi_s ,
$$

**the consistency relation** between the ramp program and the RF. Where it
does not hold, nothing is wrong: the particle gaining exactly the program's
$\Delta E_{\rm ref}$ per turn sits at the phase $k z_1 = \arcsin(\Delta
E_{\rm ref}/qV) - \varphi$, the bucket's centre moves there, and the bunch
follows it -- bucket motion, section 4's third target. With $\varphi$
programmed to $\varphi_s(n) = \arcsin(\Delta E_{\rm ref}(n)/qV(n))$ the
bucket's centre stays at $z_1 = 0$, the design arrival.

## 3. The route: a knob on the reference, a scheduled action, the recompile

Everything the ramp needs exists but one loop check:

- **The reference is a knob expression.** `ReferenceParticle(:proton; E0 =
  @knob_expr(ramp.E0))` (R4, batch A) derives $p_0c$, $\gamma_0$, $\beta_0$
  and $B\rho$ as expressions over the knob, the lattice's entrance reference
  carries them, and a cavity built with `reference = ref` stores its
  `beta0`, `gamma0` and -- on the voltage route -- its `strength =
  qV/(\beta_0 E_0)` as expressions, so its normalisation follows the knob.
  The implementation verifies this on the cavity (a probe, then a pin): a
  cavity whose strength did not follow the knob would deliver a growing
  fraction of its voltage as the energy rose.
- **The program is a turn table.** `ReferenceRamp(program; reference)` holds the
  reference energy per turn, $E_0(n)$ for $n$ in the program's window, as a
  `TurnTable`-class table (content-addressed by digest, the sidecar and the
  artifact's `/machine_tables` already carry such tables, D13), so any
  program is representable and a parametric one (linear, parabolic, a
  sinusoidal RHIC-style ramp) is a constructor that fills the table.
  Implemented: the table stores $E_0(n)$ in eV, content-addressed by its
  SHA-256 (the snapshot's bulk-table digest); `reference` is the lattice's
  `ReferenceParticle`, whose energy must be a bare knob reference in any of
  the four spellings, and the action converts each entry to the
  reference's typed key when it assigns the knob, by the reference's own
  formulas, so the receipt and the snapshot carry energies. Entry $i$ is
  turn `start_turn + i - 1`; the first entry holds before `start_turn` and
  the last after the program ends (the flat top is physics, not an error).
  Companion programs, `companions = (knob_path => values, ...)` of the
  program's length, are assigned at the same boundaries (and set to the
  first turn's value as a window starts, before the artifact's snapshot),
  the RF phase program `synchronous_phase_program(E0, V; charge)` builds
  among them, so a non-linear ramp's $\varphi_s(n)$ and a frequency
  program ride with the energy (the owner's choice 3).
- **The action, placed last in the line.** A scheduled action
  (`AbstractBeamAction`, `src/tasks/BeamObservers.jl`) placed as the LAST
  hook of the top-level line, so it fires at the end of turn $n$, after the
  cavity has delivered the turn's energy: with $n+1$ inside the program it
  computes $\rho$ from the current reference (the knob's value) and the
  table's entry for $n+1$ through the reference's `mc2`, applies the
  section-2 map to the representation on its backend (two broadcast
  multiplications and one fused multiply-add, `pz' = fma(rho, pz, rho - 1)`,
  one rounding and the same instruction on host and device), and assigns
  the knob `set_knob!(knob, E_0(n+1))`, which bumps the knob epoch. Turn $n$
  is tracked at $E_0(n)$ and the program's first entry must equal the
  reference the run starts from (checked before any turn runs, refused by
  name otherwise). A program entry equal to the current reference assigns
  nothing and rescales nothing (no epoch move, no recompile; bitwise the
  identity), so a staircase program recompiles only at its steps. Any
  other placement is refused by name with the remedy: a task-level action
  runs at the START of a turn (`run_actions!` precedes the turn's tracking)
  and would move the reference before the cavity's kick; a mid-line
  placement would leave the elements after it on the old normalisation
  for the rest of the turn (the flat-profile error of section 1, but
  avoidable, so not allowed).
- **The one extension: the epoch check in the turn loop.** Today the task
  compiles its line once per `execute!` (`_runtime_entries`, keyed on the
  knob and spec epochs; the knob note's "next-`execute!` granularity"). A
  per-turn ramp needs the check at the top of each turn, before the turn's
  plan is chosen: one atomic read per turn, a recompile only when the epoch
  moved, the compiled entries, the physics line, the hook entries and the
  strong-beam list re-derived together. The first implementation refuses
  the ramp beside a `PhaseSpaceReset` or particle tunes, whose state binds
  to one compiled line, by name. Implemented: the compile cache's unit is
  the whole line (`_runtime_entries`, keyed on the knob and spec epochs),
  so a step recompiles every entry, the plain-number magnets included, and
  rebuilds the turn plans; a line with no knob-dependent element ignores
  the knob epoch, as the cache does, and recompiles nothing. Measured
  (`validation/reference_ramp.jl`, one particle, one thread): 55 us per
  step on the 4-entry F16 ring and 4.7 ms per step on a 162-entry FODO
  line with its cavity, against 2.7 us and 43 us per turn without a step.
  A ramp that moves the knob every turn pays it every turn by
  construction -- the staircase is the lever -- and the selective
  recompile of the knob-dependent entries alone is the follow-up row.
- **The artifact (R9).** The program is a table by digest beside the declared
  machine, never a snapshot per turn: the ramp hook is written by the
  snapshot's hook rules with its table reference, the artifact's
  `/machine_tables/<sha256>` holds the table, and a `:reference_ramp`
  receipt per `execute!` names the program's digest, the window it served
  and the energies at its ends. The machine's `machine_sha256` is one digest
  for the whole ramp, as the declared machine is one object.
- **What is unchanged.** `ThinAcceleratingCavitySpec` stays SINGLE-PASS and
  its refusal stands: the ramp route uses the ring cavity and the boundary
  step, so no accelerating cavity sits in a ring. R7's "the single-pass
  refusal relaxed for that route only" turns out to be unneeded -- the
  accelerating cavity is a linac element and the ramp never passes through
  one -- and this note records the departure rather than relaxing a refusal
  nothing needs relaxed. The kernels, the compile walk and the strong-strong
  facility are untouched by the first implementation (section 5).

Magnets on a ramp. A synchrotron's magnets track the beam: $B \propto P_0$,
so the normalised strength $k = qB/P_0$ is constant and the optics are
invariant along the ramp. A magnet declared by a normalised strength
(`k1 = 1.2`) therefore needs nothing and gets nothing: it is not
knob-dependent and is not recompiled. An element whose PHYSICAL quantity is
fixed while $P_0$ moves -- a fixed-voltage cavity, a kicker at fixed field,
the strong beam at fixed intensity -- is written as a knob expression over
the reference (`strength` through `voltage = ` and `reference = ref`;
`kbb = @knob_expr(kbb_ref * E0_ref / ramp.E0)`), the sharing discipline of
the survey note's case 3, and renormalises at every step. The two cases are
the two things a control room does with a supply: ramp it with the
reference, or hold it.

## 4. Validation targets: the contract the implementation must meet

Fixture: the F16 ring of the suite (`test/runtests.jl`, "RF velocity slip
closes the full slip factor"): $C = 100$ m, a pure drift, a `Linear6DSpec`
$R_{56} = -\alpha_c C$ with $\alpha_c = 0.2$, one `ThinRFCavitySpec` at
harmonic 1 ($f = 2.99792458$ MHz), proton, $E_0 = 2.5$ GeV ($\gamma_0 =
2.66$, above transition, $\gamma_t = 1/\sqrt{\alpha_c} = 2.24$), $V = 200$ kV
(the voltage at which the linearised $\nu_s$ formula is in its regime, the
suite's 5e-3 tolerance). The ramp: $E_0$ from 2.5 to 3.5 GeV, linear in the
turn, over 10,000 turns ($\Delta E_{\rm ref} = 100$ keV per turn,
$\sin\varphi_s = 0.5$). Every target is measured on the ramped run and
compared with the formula evaluated at the energy of the measurement.

1. **Adiabatic damping, exact.** A Gaussian bunch of $10^4$ particles on
   the ring without its cavity (a linear 4D rotation added so the transverse
   planes have a tune), ramped: $\varepsilon_x(n)\,P_0(n) /
   (\varepsilon_x(0)\,P_0(0)) = 1$ to $10^{-12}$ at every recorded turn,
   and likewise $\varepsilon_y$; the covariance determinant of the
   longitudinal plane scales by $\rho^2$ per step to the same tolerance.
   The bitwise control: a program with $E_0(n)$ constant is the identity on
   the coordinates, bit for bit, and moves no epoch.
2. **The synchrotron frequency follows the program.** A particle at
   $\delta = 10^{-4}$, $z = 0$ (with $\varphi = \varphi_s$ programmed), its
   small-amplitude oscillation timed by zero crossings in windows of 2,000
   turns: the measured tune in each window within 1% of
   $$\nu_s = \sqrt{\frac{h\,\eta\,qV\cos\varphi_s}{2\pi\,\beta_0^2 E_0}},
   \qquad \eta = \alpha_c - \frac{1}{\gamma_0^2},$$
   evaluated at the window's mid-turn energy. Along this ramp $\eta$ goes
   from 0.059 to 0.128 and $E_0$ by 1.4, so the window tunes differ by a
   factor near 1.2 (measured 1.14 between the first and the last window,
   whose mid-turn energies are 2.6 and 3.4 GeV) -- a test the static
   fixture cannot pass by accident. The static control is the F16 testset
   itself. Implemented: `validation/reference_ramp.jl`, every window
   within 0.7%.
3. **Bucket motion.** (a) With $\varphi = \varphi_s(n)$ programmed, the
   particle launched at $(z, \delta) = (0, 0)$ stays within $10^{-9}$ in
   both over the ramp (the consistency relation held exactly). (b) With
   $\varphi = 0$ held and the same program, the centre of the small-amplitude
   oscillation moves to $z_1 = \arcsin(\Delta E_{\rm ref}/qV)/k$, measured
   as the mean $z$ over one synchrotron period against the formula to 1%.
4. **Effectiveness and refusals.** The ramp's knob must be one the lattice's
   reference depends on (a reference whose energy is a plain number, or an
   expression other than a bare knob, is refused by name at the ramp's
   construction, and a lattice reference that is not the ramp's at
   `execute!`); the `:reference_ramp` receipt carries the digest, the window
   and the end energies; the artifact reads the program back through its
   table. Implemented differently from the first text: a program shorter
   than the window is not refused as a turn table is -- the program holds
   at its ends (a flat top), and a window that reaches no step of any
   program warns once by name. The refusals that landed: the placement's
   (last in the top-level line, one ramp, `AlwaysSchedule` only, never a
   task-level hook, not beside a `PhaseSpaceReset` or particle tunes, not in
   a `StrongStrongTask`), the run's (a ring cavity whose `beta0` or
   `strength` is a plain number, the lattice reference mismatch, a knob not
   at the program's value for the window's first turn) and the
   constructor's (an empty or non-finite program, an entry at or below
   `mc2`, a companion of another length or on the reference's own knob).

## 5. Scope, and the owner's choices

- **First implementation: the single-beam `TrackingTask`.** The weak-strong
  strong beam rides along through a knob expression on `kbb`. The
  strong-strong task's kick scales are derived from the beams' references at
  preflight (batch A, R5) and its two beams would each need the boundary map
  and a per-turn re-derivation of `kbb1`/`kbb2`; deferred, its own batch.
- **Transition crossing is out of scope.** The fixture stays above transition;
  a program crossing $\gamma_t$ needs the phase jump and is a study of its
  own.
- **The owner's choices (2026-11-27, put to the owner with this note's
  recommendations, all four taken):** (1) the first implementation covers
  the single-beam `TrackingTask` only, transition crossing out of scope;
  (2) the program is a content-addressed turn table of $E_0(n)$, parametric
  helpers filling it; (3) the RF phase stays the user's, through a knob
  program a helper builds from the energy table and the voltage, a mismatch
  being the bucket motion of target 3b and never hidden; (4) a normalised
  strength given as a plain number stays constant -- the magnets track the
  beam -- and only an element written as a knob expression over the
  reference renormalises.

## 6. What the implementation lands with

The action type with its option schema and snapshot registration, the
turn-loop epoch check with its cost measured and recorded, the boundary map
on the CPU and CUDA backends (bitwise identical, two multiplications and one
fma, pinned in the suite; a run divided across MPI ranks refuses line
actions, the ramp included, so the map reaches MPI at one rank only and
its lifting is a follow-up), the `:reference_ramp` and
`:reference_ramp_recompiles` receipts and the program's table in the
artifact's `/machine_tables` through the embedded snapshot, the
lattice-dependence refusal, the four targets above as suite testsets (1,
3a, 4) and a validation script with its record (2, 3b), the docstrings and
`docs/public_api.md`, the design notes' status lines, and the batch record
with the neighbour audit. Every target was red first on the tree without
the action (`result/gates/ramp/red/`, `ReferenceRamp` undefined).

Implemented 2026-11-27: `src/tasks/ReferenceRamp.jl` (the action, its
schema, the helper, the compile and run checks, the epoch predicate), the
turn loop of `_execute_tracking_task!` (src/tasks/Tasks.jl), the codec in
src/lattice/toml_hooks.jl, the knob-root walk's hook arm
(src/elements/beam_line.jl), the digest scan of src/lattice/toml.jl, the
metadata validator's action block and the strong-strong refusal
(src/tasks/strongstrong/interface.jl). Measured: target 1 to $< 10^{-12}$
over a 10-step staircase on $10^4$ particles; target 2 within 0.7% in
every 2,000-turn window; target 3a at $4\times 10^{-12}$ m and
$10^{-15}$ in $\delta$ over the 10,000-turn ramp; target 3b within 0.4%
of $z_1 = 8.333$ m. The record carries the tables.
