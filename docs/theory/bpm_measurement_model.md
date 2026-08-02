# Beam Position Monitors: What a Measurement Is

A `MomentObserver` reports what the beam *is*. A BPM reports what a device
*would read*, which is a different quantity and is the one a real correction
algorithm consumes. The gap between them is the whole content of this note.

Octopus's existing diagnostics are truth: exact moments, no offset, no gain, no
noise. That is correct for physics studies and wrong for anything that has to
survive contact with an orbit-correction loop, a beam-based alignment routine,
or a response-matrix measurement — all of which are dominated by the fact that
the monitor is not perfect and is not exactly where the drawing says.

## 1. The four reference codes

Each was read from primary source rather than from memory.

### Accelerator Toolbox

`atmat/pubtools/LatticeTuningFunctions/errors/bpm_matrices.m` and
`bpm_process.m`. Fields set by `atsetbpmerr`: `Offset` (reading offsets),
`Scale` (`1 + gain error`), `Reading` (per-plane resolution sigma), `Rotation`
(roll about $s$). The reading is

$$X = R_\text{el}\,(x,y)^\top + T_\text{el} + T_\text{rand}\odot\xi,$$

with, in AT's own notation,

    tel = scale .* (rb * r1 * t1 + tb)
    rel = [scale scale] .* (rb * r1)

so, expanded, $X = s \odot \big(R_b R_1 ((x,y) + t_1) + t_b\big) + \sigma\odot\xi$.
Note that the *mechanical* offset $t_1$ is rotated by the BPM roll $R_b$ while
the *electrical* offset $t_b$ is not. That is not sloppiness; they are different
physical quantities and they compose differently.

### MAD-X

`src/mad_dict.c` defines `EALIGN` with `mrex, mrey, mredx, mredy, arex, arey,
mscalx, mscaly`. `doc/usrguide/error/error_align.html` defines them:

> **MREX**: The horizontal read error for a monitor. This is ignored if the
> element is not a monitor. If MREX>0 the reading for x is too high.
>
> **MSCALX**: The relative horizontal scaling error for a monitor. … A value of
> 0.5 implies the actual reading is multiplied by 1.5.

So MAD-X's model is exactly

$$x_\text{read} = (1 + \text{MSCALX})\,x_\text{true} + \text{MREX}.$$

Offset and gain only: no roll in the reading, no noise, no resolution. And the
attributes are *ignored on any element that is not a monitor* — the readout
error is a property of the instrument, not of the lattice.

### Bmad

Attributes confirmed in `bmad/modules/attribute_mod.f90`; the formula is manual
§28.1.1. For `instrument`, `monitor`, `detector` and `marker`:

$$\begin{pmatrix}x\\y\end{pmatrix}_\text{meas} = n_f\begin{pmatrix}r_1\\r_2\end{pmatrix} + M_m\left[\begin{pmatrix}x\\y\end{pmatrix}_\text{true} - \begin{pmatrix}x\\y\end{pmatrix}_0\right]$$

$$M_m = \begin{pmatrix}(1+dg_x)\cos(\theta+\psi) & (1+dg_x)\sin(\theta+\psi)\\ -(1+dg_y)\sin(\theta-\psi) & (1+dg_y)\cos(\theta-\psi)\end{pmatrix}$$

with $\psi$ a "crunch" (a shear that makes the two planes non-orthogonal) and
every error paired against a calibration:

$$x_0 = x_\text{off} - x_\text{calib},\quad \theta = \theta_\text{err} - \theta_\text{calib},\quad dg_x = dg_{x,\text{err}} - dg_{x,\text{calib}},\ \dots$$

The pairing is the best idea in any of the four. It lets a study set the errors,
run an analysis that *estimates* them, put the estimates in the calibration
fields, and measure how much of the error the software correction actually
removed. Bmad also carries `n_sample`, `de_eta_meas`, dispersion errors and
`osc_amplitude` for phase and dispersion measurements.

Note the sign: Bmad **subtracts** its offset, MAD-X and AT **add** theirs.

### Elegant

Not verified from source for this note. Its `MONI`/`HMON`/`VMON` elements are
known to carry calibration factors and readout expressions, but the exact
parameter set and composition order were not confirmed, so nothing here rests
on it.

## 2. The trap that decides the architecture

The obvious design — a BPM is a zero-length element carrying `x_offset`, like
every other Octopus element — **does not work**, and it fails silently.

AT states the reason in `bpm_matrices.m`:

> Since particle coordinates are accessed after the exit of the element,
> position errors introduced by T1,T2 are not visible since the reference orbit
> is back to nominal. This function takes care of that.

Octopus has exactly the same property, and it is not an accident: it is what
`_misalign_frames` is *for*. The entrance map takes the particle into the body
frame and the exit map returns it to the design frame, so for a zero-length
element with an identity body map the two cancel. Measured:

| element | map output |
|---|---|
| `MarkerSpec()` | `[0.003, 0.0003, -0.002, -0.00022, 0.002, 0.0011]` |
| `MarkerSpec(x_offset=1e-3, y_offset=-8e-4)` | identical, difference `0.0` |

The misalignment machinery runs — the runtime object really is a
`MisalignedElement` — and the map is bit-identical. A BPM built this way would
accept an offset, report it in `element_help`, pass metadata validation, and
read the true orbit. It is the exact failure mode the
`ElementParameterEffectivenessContract` exists to catch, which is a good sign
that the contract would catch it, and a better sign that the design is wrong.

**A BPM offset is not a misalignment.** A misalignment changes where a *field*
acts on the beam. A BPM has no field. Its offset changes where the *origin of
the measurement* sits, which affects only the number reported and never the
particle. Putting it in the map is a category error, and the map is honest
enough to return zero for it.

## 3. Decision: an observer bound to a position

`docs/todo.md` asked whether a BPM is "an element that observes, or an observer
bound to a position". It is the second.

- The readout error model belongs in the readout. Section 2 shows the element
  map is structurally incapable of carrying it. Even AT, whose BPM *is* an
  element, computes its reading in a separate pair of functions that
  post-process orbit data.
- Octopus already has positional observers. A `ScheduledObserver` placed inside
  the element line runs at that point in the line —
  `_execute_tracking_task!` builds a tracking plan from `runtime_entries` and
  `prepare_line_observers!` handles them. Nothing new is needed to give a BPM a
  location.
- The other three codes make a BPM an element because an element is the only
  positional entity they have. That is evidence about their architecture, not
  about the physics, and Octopus should not import a constraint it does not
  share.
- It keeps the `AbstractTrackOp` interface free of things that do not transform
  particles, which is what `PlaceholderPolicy` and the patch/misalignment split
  are already protecting.

The cost is that a BPM will not appear in `summarize_registry()`'s element list
and will not be discoverable through `element_help`. That is the right trade —
it is not an element — but it does mean BPM discovery needs its own answer, and
observers currently have no naming scheme. See Section 6.

## 4. The model Octopus adopts

$$\begin{pmatrix}x\\y\end{pmatrix}_\text{read} = \begin{pmatrix}1+g_x & \\ & 1+g_y\end{pmatrix} R(\theta)\left[\begin{pmatrix}\bar x\\ \bar y\end{pmatrix} - \begin{pmatrix}d_x\\ d_y\end{pmatrix}\right] + \begin{pmatrix}b_x\\ b_y\end{pmatrix} + \begin{pmatrix}\sigma_x \xi_1\\ \sigma_y \xi_2\end{pmatrix}$$

where $(\bar x, \bar y)$ is the **centroid** of the surviving particles, and

| symbol | field | meaning |
|---|---|---|
| $d_x, d_y$ | `x_offset`, `y_offset` | where the BPM body sits; a beam on the design axis reads $-d$ |
| $\theta$ | `tilt` | roll of the BPM about $s$ |
| $g_x, g_y$ | `x_gain`, `y_gain` | relative calibration error; MAD-X's `MSCALX` |
| $b_x, b_y$ | `x_readout`, `y_readout` | additive electrical bias; MAD-X's `MREX` |
| $\sigma_x, \sigma_y$ | `x_noise`, `y_noise` | per-reading resolution, one standard deviation |

Two design points worth stating because they are the ones a reader will
question.

**Why both an offset and a readout bias.** For a pure translation they are
algebraically redundant — $b$ can absorb $d$. They differ in how they compose:
$d$ is inside the rotation and the gain, $b$ is outside both. That is AT's
distinction between $t_1$ and $t_b$, and it is physical: a displaced pickup is
seen through the BPM's own rotated, mis-scaled axes, an electronics zero-offset
is not.

**Why the offset subtracts.** A BPM displaced by $+1$ mm reports a beam on the
design axis at $-1$ mm. Bmad's sign. MAD-X and AT add theirs because their
`MREX`/`Offset` is a *reading* bias, not a body position — which is why this
model carries both, and why they have different names here.

The model reduces exactly to the reference codes in their limits, which is a
checkable claim and not a decorative one:

- $d = \theta = \sigma = 0$ gives $x_\text{read} = (1+g_x)\bar x + b_x$,
  MAD-X's formula with $g \to$ `MSCALX`, $b \to$ `MREX`.
- $b = 0$, crunch $= 0$ gives Bmad's $n_f\xi + M_m[(x,y) - (x,y)_0]$.

## 5. Noise must be reproducible

The noise term is the only stochastic part of Octopus's diagnostics, and it goes
through `octopus_normal(seed, method, turn, rng_id, particle_index, component)`
like every other stochastic consumer, with the BPM holding an `rng_id` from
`next_rng_id!()`. This is not incidental: a counter-based draw indexed by turn
makes a BPM reading reproducible across CPU and CUDA, independent of evaluation
order, and identical whether a run is done in one call or split into chunks —
the same property the tracking RNG already guarantees and the same reason
`counter_rng.jl` exists.

A BPM that used `randn()` would break the chunked-execution invariant that
`TrackingTask absolute turns survive chunked execution` already tests for.

## 6. Deliberately out of scope for the first version

- **Crunch.** Bmad's $\psi$ shear. One more parameter in the same matrix; add it
  when something needs a non-orthogonal BPM.
- **The error/calibration pairing.** The best idea in Bmad's model, and a pure
  subtraction, so nothing is lost by deferring it: a study can subtract its own
  estimates today. Worth adding when a beam-based-alignment study exists to use
  it, which is the same "wait for the second consumer" rule `docs/todo.md`
  applies to element names.
- **`n_sample`, dispersion, phase and coupling measurements.** These need a
  measurement model per observable, not per monitor.
- **Single-plane monitors** (`HMON`/`VMON`). A one-line restriction once someone
  needs it; not obviously worth a second type.
- **Charge/intensity dependence and nonlinear button response.** Real BPMs have
  both. Both need a device model this note does not attempt.
- **Naming and discovery.** A BPM needs an identity to be useful in a
  correction study, and observers have no naming scheme. `docs/todo.md` holds
  "element names fleet-wide", waiting for a second consumer — the BPM is *not*
  that consumer, since it is not an element, but it does establish that
  observers need the same thing. Recorded rather than solved here.

## 7. How this gets validated

There is no external reference to compare a BPM reading against — it is a
definition, not a physical law, so a PTC-style comparison does not apply. The
checks that do mean something:

1. **The zero-error BPM reproduces the moment observer's centroid exactly.**
   With all errors zero the reading must equal $\langle x\rangle$ to round-off,
   which ties the new path to the existing validated one.
2. **Each error term reaches the reading**, in the spirit of
   `ElementParameterEffectivenessContract`: setting any one of the nine to a
   non-default must move the number. Section 2 is the cautionary tale.
3. **MAD-X's formula is reproduced** in the limit of Section 4 — a direct
   numerical check against $(1+\text{MSCAL})x + \text{MRE}$.
4. **The reading does not perturb tracking.** A BPM is passive; a line with one
   must track bit-identically to a line without one.
5. **Noise is reproducible** across chunked execution and across backends, and
   its sample statistics match the requested $\sigma$.
