# U16 — RF cavity / patch / boost / ref_tilt / chromaticity + examples/

Reading unit of the comprehensive audit protocol. Repo
`/cfs/ad/dxu/Library/Julia/Octopus`, **HEAD `7de4d81`** (clean at start; the only
tree modification during the session was `docs/history/comprehensive_audit_2026_08_05_b.md`,
written by another party — this unit modified no repository file).

Predecessors: `docs/history/comprehensive_audit_2026_08_05_unit_reports/U12_report.md`
(baseline `e0fbda`) and `U18_report.md` (baseline `83e1d38`). 63 commits landed
since the last declared audit point `6a3f39ab`; the region diff was read first.

---

## 1. Provenance

### Read, every line

| file | lines |
|---|---|
| `src/elements/rf_cavity.jl` | 1–252 |
| `src/elements/patch.jl` | 1–210 |
| `src/elements/chromaticity_kick.jl` | 1–206 |
| `src/elements/crab_cavity.jl` | 1–194 |
| `src/elements/lorentz_boost.jl` | 1–174 |
| `src/elements/ref_tilt.jl` | 1–137 |
| `examples/weak_strong_tracking.jl` | 1–289 |
| `examples/strong_strong_tracking.jl` | 1–264 |
| `examples/knob_control.jl` | 1–159 |

Plus the assigned context: `AGENTS.md` §Hard-Won Rules (79–105) and §Updating
Examples (333–348); `docs/comprehensive_audit.md` §Measured Lessons (709–803);
`git diff 6a3f39ab HEAD` over the whole region.

### Cross-read (bounded, for verification only — not audited)

`docs/theory/rf_cavity_and_reference_energy.md` (whole file, §4/§6-Step-0/§8/§9
in detail); `docs/theory/misalignment_and_patch_maps.md` §7/§8;
`src/track/longitudinal.jl` 150–235; `src/elements/misalignment.jl` 48–95,
197–215; `src/elements/beam_line.jl` 559–616; `src/knowledge/Knowledge.jl`
72–102, 520–535, 1030–1067; `src/contracts/Contracts.jl` 1172–1300, 2035;
`test/runtests.jl` 2218–2325, 5300–5385; `validation/crossing_luminosity_anchor.jl`
1–60; `validation/tracking_backend_consistency.jl` 140–150; `docs/todo.md` (F16 row).

### Executed

Probes in `<scratch>/audit/`, all CPU, Julia 1.12.4, ForwardDiff 1.4.4 supplied
through a scratch env on `JULIA_LOAD_PATH` (the repo project has it as a weakdep
only):

```
env JULIA_LOAD_PATH="/cfs/ad/dxu/Library/Julia/Octopus:<scratch>/audit/fdenv:@stdlib" \
    julia --startup-file=no <probe>.jl
```

- `p1_rf_slip.jl` — F16 reproduction, built independently of U12's harness
- `p2_rf_claims.jl` — the recorded correct claims, re-measured at three energies
- `p3_boost_patch_tilt_chrom.jl` — boost invertibility + Hirata cross-check;
  patch/ref_tilt/chromaticity against independent derivations; bitwise identity limits
- `p4_conventions.jl` — patch rotation sense, numeric promotion, unknown-key warnings
- `p5_patch_ref.jl` — `_patch_reference_length` vs the on-axis reference particle
- `p6_reftilt_line.jl` — `RefTilted` over a `CompositeLine`; F16 discoverability
- `p7_f32.jl`, `p8_f32track.jl` — Float32 promotion and kernel type stability

**Examples were run verbatim.** A scratch tree `<scratch>/audit/run/` holds
byte-identical copies (`cmp` clean) of the three scripts under `run/examples/`
with `run/src -> /cfs/ad/dxu/Library/Julia/Octopus/src` symlinked, so each
script's own `joinpath(@__DIR__, "..", "result")` resolves to
`<scratch>/audit/run/result/`. **Nothing was written into the repository tree**
(verified: `git status --porcelain` clean apart from the foreign file above, and
no new file under `result/`). No source line of any example was altered.

### Not checked, and why

- **CUDA.** No GPU probe was run. The region's CUDA exposure is the shared
  `ElementTrackingBackendConsistencyContract` line, which is a cross-file seam,
  and the Float32 finding (U16-8) is stated from CPU type measurement only — its
  device consequence is inferred, not measured.
- **PTC/Bmad reference cases.** `_misalign_matrix`'s pinning against PTC is
  taken as given from `quad_mis_all`/`cfbend_mis_all`; this unit did not re-run
  them. U16-5 is a claim about the *sense in which the patch applies* that
  matrix, not about the matrix.
- **`test/examples/` harnesses.** Out of region (U18's territory).
- **Full-suite gate.** Not run; this unit only reads and measures.

---

## 2. LEADS

### LEAD U16-1 [Low, confidence high] docs/theory/rf_cavity_and_reference_energy.md:160,163 (also docs/todo.md, F16 row)

**Claim:** The F16 correction block sends a future fixer to the wrong section —
it cites "§7's checks" and "§7's own criterion (`ν_s` against the **full** `η`)",
but §7 is *"The self-referential phase, which has to be decided not discovered"*;
the ν_s criterion is **§8 item 4** (lines 276–279). The same wrong number is
copied into the `docs/todo.md` F16 row ("The theory note's own §7 criterion").
And §8 item 4 itself carries **no annotation** that it is the check that would
fail, so a reader arriving at §8 sees an ordinary not-yet-done validation item.

**Mechanism:** Documentation cross-reference, hand-copied into a second place.
The audit's own Measured Lesson 4 ("hand-copied knowledge always drifts") applies:
the correction was written once and the section number transcribed twice, and the
one section that *should* carry the marker (§8, the validation list) is the one
place the correction does not touch.

**Repro:**
```
grep -n "^## " docs/theory/rf_cavity_and_reference_energy.md
#   -> 255:## 7. The self-referential phase ...   269:## 8. How this gets validated
grep -n "§7's" docs/theory/rf_cavity_and_reference_energy.md
grep -n "§7 criterion" docs/todo.md
sed -n '276,279p' docs/theory/rf_cavity_and_reference_energy.md   # the nu_s criterion, unannotated
```

---

### LEAD U16-2 [Medium, confidence high] docs/theory/rf_cavity_and_reference_energy.md:88-89 and 285-288

**Claim:** The theory note — the design authority the element's
`construction_help` points at — still asserts the cross-element phase identity
that the element docstring now explicitly disclaims. §4 line 88: *"the argument
is `kz + φ`, **additive**, taken against Octopus's own longitudinal coordinate"*,
followed by *"The accelerating cavity must match this"*; §9 item 1: *"~~Phase
convention?~~ **Settled: follow `ThinCrabCavity`** — ... argument `kz + φ` (§4).
... two RF elements in one lattice must not mean two different things by
`phase`."* The code and the element docstring (`rf_cavity.jl:156-159`) now say
the argument is `k·z₁ + φ` and that it *"coincides with `ThinCrabCavity`'s `k*z`
only at `β = 1`"*. The U12-2 fix landed on the element, the ParamMeta and the
construction_help, and did not reach the note.

**Mechanism:** One-directional fix. The note→code link was repaired at the code
end only, so the note now contradicts the element it specifies — the same shape
the 2026-08-05 audit recorded for F16 itself ("the note→code link carried the
same defect at both ends").

**Repro:** measured discrepancy at the note's own worked point —
```julia
# proton E0 = 2.5 GeV, z = 7.0e-3 m, delta = 2.3e-3, f = 400.8 MHz
b0, g0 = reference_beta_gamma(2.5e9, PMASS_EV)
z1, _  = convert_longitudinal(PATHLENGTH_DELTA => TIME_ENERGY, 7.0e-3, 2.3e-3; beta0=b0, gamma0=g0)
k = 2pi*400.8e6/CLIGHT
k*z1 - k*7.0e-3        # -> 0.004616872549326481 rad     (p2_rf_claims.jl)
```
i.e. 4.617e-3 rad — the element docstring's "4.6e-3 rad", which the note says
cannot happen.

---

### LEAD U16-3 [Low, confidence high] src/elements/rf_cavity.jl:251 (`construction_help`)

**Claim:** The velocity-slip model boundary is documented on the human docstring
and in the theory note, but **not** on `construction_help` — the string
`element_help(:thin_rf_cavity)` prints and the agent-facing discovery surface an
AI-native framework advertises. The same string *does* document the other two
boundaries ("there is no transit-time factor and no RF focusing"), so the
omission reads as "these are all the boundaries there are". No `ParamMeta`
`meaning` mentions it either.

**Mechanism:** The F16 documentation pass updated the `_rf_kick` docstring, the
`ThinRFCavitySpec` docstring and the `phase` ParamMeta, and extended
`construction_help` only with the generic `_PLACEMENT_PARAMS` sentence. A user
reading `?ThinRFCavitySpec` sees the boundary; an agent calling
`element_help(:thin_rf_cavity)` or `construction_help(...)` does not.

**Repro:**
```julia
ch = construction_help(ElementSpec{:thin_rf_cavity})
occursin("transit-time", ch)   # true
occursin("slip", ch)           # false
occursin("velocity", ch)       # false
any(occursin("slip", string(v.meaning)) for v in values(parameter_schema(ElementSpec{:thin_rf_cavity})))  # false
occursin("velocity-slip", string(@doc ThinRFCavitySpec))   # true  (the human end is fine)
```
(`p6_reftilt_line.jl`, section B.)

---

### LEAD U16-4 [Medium, confidence high] src/elements/patch.jl:118-127 (`_patch_reference_length`)

**Claim:** `_patch_reference_length` returns the new origin's displacement
**projected** onto the new `s` axis, and its docstring says *"This is what the
on-axis reference particle traverses."* Measured: the on-axis, on-momentum
particle traverses the **unprojected** distance. A patch carrying both a `dz`
and a transverse-axis rotation therefore shifts the reference particle's `z` by
exactly `dz·(cos θ − 1)`, and the docstring's headline identity
("composing a patch with its exact inverse is the identity",
`patch.jl:159-160`, repeated in `construction_help`) fails in `z` by the same
amount.

**Mechanism:** For `dz = D`, `angle_y = θ` and the on-axis particle,
`_patch_map` computes `q3 = cos θ`, `ds = D cos θ`, so
`path = ds·(1+pz)/q3 = D` (the true distance to the new face) while
`ref = _patch_reference_length = D cos θ`. `z_out = z + ref − path = z − D(1−cos θ)`.
The two lengths are only equal when the rotation is absent (single-parameter
patches all round-trip at ≤ 6.7e-18, which is why nothing caught it). The same
shape appears for a transverse offset plus a rotation.

**Repro:**
```julia
compile_runtime(PatchSpec(dz=0.23, angle_y=0.013))(0,0,0,0,0,0)[5]
#  -> -1.943472629195586e-5      == 0.23*(cos(0.013)-1) = -1.9434726291969184e-5
compile_runtime(PatchSpec(dz=1.20, angle_y=0.0125))(0,0,0,0,0,0)[5]   # -9.374877930312664e-5
compile_runtime(PatchSpec(dz=0.50, angle_y=0.100 ))(0,0,0,0,0,0)[5]   # -2.4979173609870897e-3
compile_runtime(PatchSpec(dx=0.05, angle_y=0.013))(0,0,0,0,0,0)[5]    #  5.492732075120313e-8
# controls: dz alone, angle_y alone, angle_s with dz  ->  exactly 0.0
```
and the round trip against the exact geometric inverse
(`dx',dy',dz' = -W·o`, `angle_y' = -θ`) leaves residual
`[-3.3e-19, -6.1e-19, 0.0, 0.0, -1.943472629194914e-5, 0.0]` — everything at
machine precision except `z`. (`p5_patch_ref.jl`.)

**Unguarded:** `test/runtests.jl:5319-5325` inverts translation-only and
rotation-only patches; it never composes the two in one patch. This is the
hand-picked-case failure class of Measured Lesson 3/4.

---

### LEAD U16-5 [Medium, confidence high] src/elements/patch.jl:74-82 vs src/elements/ref_tilt.jl:69-70

**Claim:** The patch and the misalignment/`ref_tilt` family share
`_misalign_matrix` but apply it in **opposite senses** — the patch applies `W`
(`_patch_apply`), the frame changes apply `Wᵀ` (`_frame_change`, `_s_rotate`).
The same numeric angle therefore means the *opposite* roll in the two elements.
This sits directly against `_patch_rotation`'s stated rationale
(`patch.jl:56-62`): the routine is shared so that a patch "cannot drift away
from the magnets it sits between".

**Mechanism:** `_patch_apply(W, a1,a2,a3)` forms `W·a`; `_frame_change` forms
`Q'·a` and `_s_rotate(W[1], W[4], …)` is the written-out transpose. So
`PatchSpec(angle_s=+ψ)` rotates coordinates by `R(+ψ)` while `tilt = +ψ` /
`ref_tilt = +ψ` rotate them by `R(−ψ)`. (Whether this is a deliberate "the patch
angle names the trajectory rotation, the misalignment angle names the axes
rotation" choice is the auditor's call; the *docstring* says the patch angles
"rotate its axes", which is the transposed reading.)

**Repro:**
```julia
psi = 0.37; u = (4e-4, 1e-4, -2e-4, -1.5e-4, 1.2e-3, 2e-4)
q  = compile_runtime(QuadrupoleSpec(L=0.4, k1=0.9))
pf = compile_runtime(PatchSpec(angle_s= psi))
pb = compile_runtime(PatchSpec(angle_s=-psi))
conj = pb(q(pf(u...)...)...)
maximum(abs, collect(conj) .- collect(compile_runtime(QuadrupoleSpec(L=0.4,k1=0.9,tilt=-psi))(u...)))  # 0.0
maximum(abs, collect(conj) .- collect(compile_runtime(QuadrupoleSpec(L=0.4,k1=0.9,tilt=+psi))(u...)))  # 2.0390272307316655e-4
```
Direct form: `PatchSpec(angle_s=+ψ)` maps `(x,y)` by `[[c,-s],[s,c]]`;
`_s_rotate(W[1],W[4],…)` maps it by `[[c,s],[-s,c]]`. (`p4_conventions.jl` §1.)

---

### LEAD U16-6 [Low, confidence high] src/elements/patch.jl:155 and :208

**Claim:** The `PatchSpec` docstring's first worked example and the kind's
registered `example` are both `PatchSpec(angle_x = 12.5e-3)` captioned
"a crossing angle" — but `angle_x` rotates about x and therefore deflects
**vertically**, while every crossing angle in this repository is horizontal
(`Contracts.jl:2035` calls the boost "the horizontal-crossing boost"; every
crab cavity in `examples/` kicks in `x`; `validation/crossing_luminosity_anchor.jl`
is a horizontal-crossing case). A reader copying the registered example for the
repository's own crossing angle gets the wrong plane.

**Mechanism:** Naming, not arithmetic — `angle_x` = "rotation about the x axis"
is internally consistent; the caption is what is wrong, and it is the caption
that `element_help(:patch)` shows.

**Repro:**
```julia
compile_runtime(PatchSpec(angle_x=12.5e-3))(0,0,0,0,0,0)[[2,4]]  # (0.0, -0.012499674481709789)  -> vertical
compile_runtime(PatchSpec(angle_y=12.5e-3))(0,0,0,0,0,0)[[2,4]]  # (0.012499674481709789, 0.0)   -> horizontal
```

---

### LEAD U16-7 [Low, confidence high] examples/weak_strong_tracking.jl:40 and :106

**Claim:** `input.total_turns = 1_000_000` is **never read** — the file's
`execute!` uses `config.turns`, and the moment schedule's `stop` is the
duplicated literal `1_000_000` at line 106 rather than `input.total_turns`.
`examples/strong_strong_tracking.jl:233` does it correctly
(`stop = input.total_turns`), so the two sibling precedents disagree, and the
weak-strong one carries both a dead config field and a magic number that must be
edited in two places to stay consistent.

**Mechanism:** Examples are architectural precedents (AGENTS.md); a dead field in
the `input` block teaches that `total_turns` is how you set the run length,
which is false in this file.

**Repro:**
```
grep -n "total_turns\|1_000_000" examples/weak_strong_tracking.jl
#  40:    total_turns = 1_000_000,      <- no other reference in the file
# 106:        moment_stop = 1_000_000,
grep -n "total_turns" examples/strong_strong_tracking.jl     # 56 (definition) and 233 (use)
```

---

### LEAD U16-8 [Low, confidence high, OUT OF HYPOTHESIS] src/elements/chromaticity_kick.jl:104,110,116,117

**Claim:** `ChromaticityKick`'s tracking kernel is written with the Float64
constant `TWOPI` and the Float64 literal `0.5`, so a `ChromaticityKick{…,Float32}`
fed Float32 coordinates returns **all-Float64** output. Its siblings in this
region do not: `ThinCrabCavity` (`T(2)*T(pi)/…`) and `LorentzBoost`
(`one(pz0)` idioms) both stay in Float32. The element sits in both examples'
lines and declares the backend-consistency contract, so the promotion is on a
CUDA-reachable path.

**Mechanism:** `const TWOPI = 6.283185307179586476925286766559005768394338`
(`src/constants/Constants.jl:23`) is a Float64 literal;
`μx = TWOPI * elem.xix * pz` and `Jx = 0.5 * (…)` promote everything. The
struct's `T` parameter is honoured for storage and discarded in arithmetic.

**Repro:**
```julia
u32 = (4f-4, 1f-4, -2f-4, -1.5f-4, 1.2f-3, 2f-4)
ck = compile_runtime(ChromaticityKickSpec{Float32}(; xi=(1.2f0,-0.8f0), beta=(0.82f0,0.075f0)))
typeof(ck)                       # ChromaticityKick{Symplectic6DMap, Float32}
unique(map(typeof, ck(u32...)))  # DataType[Float64]        <- all promoted
cc = compile_runtime(ThinCrabCavitySpec{2}(1.97f8; strengthX=(1f-5,-2f-6)))
unique(map(typeof, cc(u32...)))  # DataType[Float32]        <- the sibling does not
```
Related but distinct, and a framework-level seam rather than a region defect:
`numeric_type(spec, default=Float64)` (`Knowledge.jl:526`) folds from a Float64
seed, so every kind that uses it (here `ThinRFCavity`) yields a Float64 runtime
from a Float32 spec, and `patch.jl:180-181` reproduces that floor by hand
(`promote_type(…, Float64)`). Measured: `Patch{…,Float64}` and
`ThinRFCavity{…,Float64}` from all-Float32 specs, both returning mixed
Float32/Float64 tuples. **Flagged as a seam; stopping here.**

---

### LEAD U16-9 [Low, confidence high, OUT OF HYPOTHESIS — cross-file seam] src/elements/{rf_cavity,patch,chromaticity_kick,crab_cavity,lorentz_boost}.jl `contracts = [...]`

**Claim:** The declaration↔case tripwire added for `SymplecticityContract`
(2026-08-05 audit, U3-3; `Contracts.jl:1276-1288`) can only ever see **one**
registered kind, `:solenoid`, because it is the only kind whose metadata
declares the contract. `ThinCrabCavity` and `ChromaticityKick` have hand-written
cases in `_symplecticity_contract_cases()` but declare nothing, so removing their
cases would fire nothing; `ThinRFCavity` and `Patch` — both measured exactly
symplectic in this session (≤ 3.3e-16 and 2.2e-16) — have neither a declaration
nor a case.

**Mechanism:** The tripwire is `declared ⊆ covered`. With `|declared| = 1` it is
a near-tautology. This is the "correct check, never executed" class (Measured
Lesson 1) one level up: the check runs, but its domain is empty of everything it
was built to protect.

**Repro:**
```julia
[element_meta(T).kind for T in registered_element_specs()
 if any(C -> C === SymplecticityContract, element_meta(T).contracts)]
#  -> [:solenoid]
```
(`p4_conventions.jl` §9.) Cross-file (Contracts.jl × every element's metadata) —
reported and stopped.

---

### LEAD U16-10 [Low, confidence med] examples/weak_strong_tracking.jl:65, examples/strong_strong_tracking.jl:57, src/elements/lorentz_boost.jl:71,109

**Claim:** The same physical quantity, 12.5e-3 rad, is the **half** crossing
angle everywhere it is used, but is named `crossing_angle` in both tracking
examples and `half_crossing_angle` in `knob_control.jl:44`, `Knobs.jl:651` and
`validation/crossing_luminosity_anchor.jl:14`; the `:lorentz_boost` /
`:rev_lorentz_boost` `ParamMeta` say only "boost crossing angle". Three
architectural precedents disagree on the name of the quantity whose factor of
two is the classic beam-beam error.

**Mechanism:** Naming drift across precedents. The physics is consistent — both
examples pair `LorentzBoostSpec(θ)` with a crab strength `tan(θ)/sqrt(β_cc β*)`,
which is the half-angle relation, and the boost's Hirata `φ` is the half angle —
so this is a documentation/naming lead only, not a numerical one.

**Repro:**
```
grep -n "crossing_angle" examples/*.jl validation/crossing_luminosity_anchor.jl src/knobs/Knobs.jl
grep -n 'meaning="boost crossing angle"' src/elements/lorentz_boost.jl
```

---

### LEAD U16-11 [style, confidence high] examples/weak_strong_tracking.jl:1

**Claim:** Style only. `using LinearAlgebra` sits on line 1, **above** the
top-of-file comment block (3–28), so the file's first line is code rather than
the purpose/structure/run-command comment AGENTS.md asks be placed at the top;
and the import is unnecessary — `examples/strong_strong_tracking.jl` calls the
same `inv(Matrix(Linear6D(...)))` at line 189 with no such import and runs clean,
because Octopus depends on LinearAlgebra. The two sibling precedents differ in
their preamble for no reason a reader can see.

**Repro:**
```
head -3 examples/weak_strong_tracking.jl        # `using LinearAlgebra` then the =# block
grep -n "using\|inv(Matrix" examples/strong_strong_tracking.jl   # no LinearAlgebra; inv(Matrix(...)) at 189
```
(Verified by execution: strong_strong runs to completion, exit 0, no error.)

---

## 3. Hypothesis (a) — the RF cavity's documented model boundary

### (i) Independent reproduction of the 1.84× number — CONFIRMED

Built from scratch, not from U12's harness. The ring is one arc map derived
independently from convention #3's definition `z = s − ℓ`
(`longitudinal.jl:35`): over one turn `s` advances by `C` and `ℓ` by
`C(1 + α_c δ)`, so `Δz = −α_c C δ`. The tune comes from the **eigenvalue of the
one-turn 2×2 Jacobian** by ForwardDiff (no FFT, no fitting), cross-checked
against turn-by-turn phase accumulation at three amplitudes.

Point: proton, `E0 = 2.5 GeV` total, `mc2 = PMASS_EV`; `C = 1000 m`, `h = 5`,
`V = 6 MV`, `φ_s = 0`, `α_c = 0.2`.

```
beta0                  = 0.9268998207958971
gamma0                 = 2.664472308367128
1/gamma0^2             = 0.14085672220853404
f_rev                  = 277877.5755961615 Hz     f_rf = 1.3893878779808073e6 Hz
strength (compiled)    = 0.002589276582165268     qV/(P0 c) by hand: difference 0.0

one-turn Jacobian      = [0.9999999999999999  -200.0
                          8.77597784155112e-5  0.982448044316898]
det J - 1              = 0.0
nu_s (linearised map)  = 0.021100901683886713
nu_s (tracked, 20000 turns)  = 0.021100896965588044  (z0 = 1e-5 m)
                               0.021100896936466204  (z0 = 1e-4 m)
                               0.021100896804249435  (z0 = 1e-2 m)

analytic, eta = alpha_c              = 0.021085450700955955
analytic, eta = alpha_c - 1/gamma0^2 = 0.011466228327264719   (eta_true = 0.05914327779146597)

ratio  tracked / analytic(alpha_c)   = 1.00073          <- the model matches the WRONG eta
ratio  map     / analytic(true eta)  = 1.8402652626158156   <- F16's 1.84x, REPRODUCED
sqrt(alpha_c / eta_true)             = 1.838917741662128     (the 0.07% excess is the
                                                              thin-cavity finite-tune term)
```

Mechanism isolated at the conversion itself:

```
d(k z1)/d(delta) at s = 0      = 0.0
d(k z1)/d(delta) at s = C      = 4.425144436990697
difference                     = 4.425144436990697
k*C/(beta0*gamma0^2)           = 4.425144436990688
ratio                          = 1.0000000000000022
```

so the omitted term is exactly the velocity part of `η`, and the seam
(`convert_longitudinal(...; s=...)`) already carries the fix.

**Wrong transition side, also reproduced.** At `α_c = 0.05 < 1/γ₀² = 0.1409`:
the model's one-turn trace gives `tr/2 = 0.9978` — stable synchrotron motion at
`phase = 0` — while `η_true = −0.0909` says the ring is below transition and the
stable phase must move to `π`. The model puts the bucket on the wrong side.

### (ii) Is the boundary documented at both ends? — YES, with three gaps

| surface | carries the boundary? |
|---|---|
| `_rf_kick` docstring (`rf_cavity.jl:69-83`) | **yes**, with the number, the regime, and the fix's blocker |
| `ThinRFCavitySpec` docstring (`rf_cavity.jl:161-165`) — the `?` a user types | **yes**, "Two model boundaries, stated so they are visible from the call site" |
| `phase` ParamMeta (`:243`) | partly — carries the `z₁` correction (U12-2), not the slip |
| `construction_help` / `element_help` (`:251`) | **no** — LEAD U16-3 |
| theory note §6 Step 0 correction block (`:149-164`) | **yes**, complete and quantitative |
| theory note §8 (the validation list that would catch it) | **no marker** — LEAD U16-1 |
| theory note §4 / §9 (still assert the superseded phase claim) | **contradicts the element** — LEAD U16-2 |
| `docs/todo.md` open row | **yes** (with U16-1's wrong section number) |

Wording check against the code: the docstring's `-c dt = z/beta + s*(1/beta0 - 1/beta)`
matches `longitudinal.jl:186` `_z1_of(::PathLengthDelta, z, beta, beta0, s) =
(z + s*(beta/beta0 - 1))/beta` exactly; the "electron 10 GeV has 1/gamma0² =
2.6e-9" figure checks (γ₀ = 19569.5 → 2.611e-9).

### (iii) Does anything silently rely on the wrong behaviour? — NO. But the one check that would catch it is blind by construction.

Every use of the element in the repository was enumerated
(`grep -rn 'ThinRFCavity\|thin_rf_cavity\|rf_strength' test/ validation/ examples/`):

- **`test/runtests.jl:2287-2309`** — "Synchrotron motion in a toy ring". Builds a
  ring from the cavity plus `Linear6D` with `M[5,6] = -1.0e-3  # a pure
  longitudinal slip`. The slip is a **free hand-chosen number**, never derived
  from `α_c` and `γ₀`, and the assertions are only area preservation, stability,
  and `ν_s(4V)/ν_s(V) ≈ 2`. All three are **exactly invariant** under the value
  of `η`, so the test neither relies on the defect nor can see it. It is
  precisely §8 item 4's criterion with the discriminating half removed.
- **`validation/tracking_backend_consistency.jl:144`** — CPU/GPU parity only;
  blind to the physics on both sides.
- **`examples/`** — **no example uses the RF cavity at all.** Both tracking
  examples close the longitudinal plane with a `Linear6DSpec` one-turn map that
  carries `tune[3]` directly (−0.01 proton, −0.069 electron), bypassing the
  cavity. So no architectural precedent is contaminated.
- **Contracts** — `:thin_rf_cavity` declares only
  `ElementTrackingBackendConsistencyContract`.

**Blast-radius note for whoever fixes it** (not a lead): the toy-ring test's
ratio assertions are `η`-insensitive and will survive a fix; but the test's ring
has no circumference, so whatever the arc-position channel resolves `s` to for a
two-element line becomes newly observable there. Check it at fix time.

### Recorded correct claims — all re-measured and CONFIRMED

| claim | measured |
|---|---|
| symplectic to 1e-14 | `\|J'SJ − S\|` = 1.11e-16 / 3.33e-16 / 2.22e-16 (L=0) and 1.11e-16 / 4.44e-16 / 1.67e-19 (L=2) at proton 2.5 GeV, proton 275 GeV, electron 10 GeV (ForwardDiff, exact) |
| kick exactly `qV·sin/(P0 c)` | hand-built TIME_ENERGY sandwich reproduces the map **bitwise** (`dz = dpz = 0.0`) at all three energies; `strength − qV/(β₀E₀) = 0.0` |
| `d(delta)/d(pt) = 1/beta` | difference **exactly 0.0** at all three energies (1.0785168680105603, 1.0000057938940445, 1.0000000012996144) |
| `nu_s ~ sqrt(V)` | `ν_s(4V)/ν_s(V) = 2.0044285`, `ν_s(9V)/ν_s(V) = 3.0178939` (the excess is the thin-cavity finite-tune term, matching U12's 2.0044) |
| zero voltage is bitwise identity | true at all three energies, all six components `===` |
| transverse untouched | bitwise at all three energies |
| `L → 0` equals `L = 0` | difference 2.09e-13 at `L = 1e-9`, i.e. exactly the `L·px` drift — linear in `L`, as the DKD split requires |
| voltage + explicit beta0/gamma0 now refused (U12-3 fix) | both `beta0=` and `gamma0=` raise `ArgumentError` |
| unknown-key typo now warns (U12-10) | `ThinRFCavitySpec(...; phaze=0.3)` warns and names `:phaze` |

---

## 4. Hypothesis (b) — Lorentz boost and crossing angle

### Round-trip residual (the requested measurement)

`RevLorentzBoost(θ) ∘ LorentzBoost(θ)` and the reverse, absolute max over the six
components. Small point `u = (4e-4, 1e-4, −2e-4, −1.5e-4, 1.2e-3, 2e-4)`;
large point `(5e-3, 3e-3, −4e-3, 2.5e-3, 2e-2, 8e-3)`.

| angle | point | `rev(fwd(u)) − u` | `fwd(rev(u)) − u` |
|---|---|---|---|
| 12.5 mrad | small | **4.878909776e-19** | 1.084202172e-19 |
| 12.5 mrad | large | 8.673617380e-19 | 4.336808690e-19 |
| 25 mrad | small | 3.333921680e-18 | 6.776263578e-20 |
| 25 mrad | large | 1.734723476e-18 | 2.168404345e-18 |
| 0.3 rad | small | 3.482999479e-18 | 4.106415728e-18 |
| 0.3 rad | large | 1.431146868e-17 | 3.426078865e-17 |

Worst **relative** residual over all cases: 4.77e-15 (on the smallest component).
`inverse_boost(LorentzBoost(0.0125))` round trip: 4.879e-19.

The boost is **exactly invertible to machine precision**, at production and at
ten-times-production crossing angles, at small and large amplitude.

### Crossing-angle convention

- **Against the published map.** An independent transcription of Hirata's
  crossing-angle transformation (`px* = (px − H tanφ)/cosφ`, `py* = py/cosφ`,
  `δ* = δ − px tanφ + H tan²φ`, `H* = H/cos²φ`, `x* = tanφ·z + (1 + px*sinφ/ps*)x`,
  `y* = y + py*sinφ/ps*·x`, `z* = z/cosφ − H*sinφ/ps*·x`) reproduces the code to
  **≤ 5.42e-20** (exactly 0.0 at 0.3 rad).
- **Mass shell.** The internally propagated `ps1 = 1 + pz1 − h1` equals
  `sqrt((1+pz1)² − px1² − py1²)` to ≤ 2.22e-16 — the shortcut is exact, not an
  approximation.
- **Volume factors.** `det J(fwd) − sec³θ` = 0.0 / 0.0 / −2.22e-16 and
  `det J(rev) − cos³θ` = 0.0 / 0.0 / −1.11e-16 at the three angles; the product
  `det(fwd)·det(rev) − 1 ≤ 4.44e-16` — the pair restores phase-space volume, as
  both docstrings claim.
- **Identity limit and sign.** `angle = 0` is the **bitwise** identity in both
  directions; the origin is a bitwise fixed point; and the geometric signature
  `x₁ = z·tanφ` holds **exactly** (`1.2500651082359346e-5` both sides), fixing
  the sign.
- **Agreement with the beam-beam kernels.** The convention is the **half**
  crossing angle, used with the same sign by both beams' lines. Consistent
  across `examples/strong_strong_tracking.jl:224-225` (both `line_ele` and
  `line_pro` share the same `lb`/`rlb`), `examples/weak_strong_tracking.jl:269,271`,
  and `validation/crossing_luminosity_anchor.jl:14` which names it
  `theta = 12.5e-3  # half crossing angle` and pairs it with
  `tan(angle)/sqrt(crab_beta*beta)` — the half-angle crab relation. The strong
  beam is built head-on (`angle = (0,0,0)`), i.e. the boosted frame, which is
  what the boost delivers. The only defect found is the **naming** (LEAD U16-10).

---

## 5. Hypothesis (c) — patch, ref_tilt, chromaticity_kick

### Bitwise identity limits (the requested check)

Bitwise means `===` on all six returned components, at four probe points:
`u = (4e-4, 1e-4, −2e-4, −1.5e-4, 1.2e-3, 2e-4)`; a ten-times-larger point; an
all-signs-flipped point; and the exact origin.

| element, zero-parameter form | bitwise identity |
|---|---|
| `PatchSpec()` | **true** at all four points |
| `ThinRFCavitySpec(..., strength = 0)` | **true**, all three energies |
| `ChromaticityKickSpec(xi = (0,0))` | **true** at all points |
| `ThinCrabCavitySpec{2}(f)` (all strengths zero) | **true** |
| `LorentzBoost(0)` / `RevLorentzBoost(0)` | **true**, both |
| `ref_tilt = 0` | **true** — `_ref_tilt_wrap` returns the inner object *unwrapped* (compiles to `LatticeMagnet`, not `RefTilted`), so it is identity by construction; and a hand-built `RefTilted(inner, 1.0, 0.0)` is also bitwise equal to `inner` |

One honest near-miss, correctly so: `ChromaticityKickSpec(xi=(0,0))` **with**
`zeta`/`eta`/`R` nonzero leaves 2.71e-20 — that is the conjugation's
`_inverse ∘ forward` float round trip, not a `xi`-limit failure. The documented
BPM-relevant property (zero parameters → bit-for-bit input) holds for every
element in the region.

### Independent derivations

- **Chromaticity kick — matches BITWISE (difference exactly 0.0).** Derived
  independently as the time-1 flow of `h = 2π·ξ·pz·J(x,px)`: since `J` is
  invariant under the rotation it generates, `(x,px)` rotate by `μ = 2πξ pz` in
  Twiss coordinates and `dz/ds = ∂h/∂pz = 2πξ J`, giving `z += 2π(ξ_x J_x + ξ_y J_y)`.
  A from-scratch implementation of that (rotation matrix
  `[[cosμ+α sinμ, β sinμ], [−γ sinμ, cosμ−α sinμ]]` plus the CS-action `z` shift)
  reproduces the element bit for bit. The CS action is preserved exactly
  (`J_out − J_in = 0.0`).
- **Patch, three independent routes.** (1) A pure-`dz` patch equals the exact
  `DriftSpec` drift: five of six components bitwise, `z` to 5.55e-17
  (rel 4.6e-14 — different but algebraically equivalent rounding; note this
  *corrects* U12's "bitwise including the z accounting", which holds only for the
  particular numbers that testset uses). (2) A pure-`angle_s` patch equals a
  rigid `R(+ψ)` on `(x,px,y,py)` **exactly (0.0)** with `(z,pz)` bitwise
  untouched. (3) `t_offset` alone shifts `z` by exactly `t_offset`
  (`z_out − z_in − t_offset = 0.0`) with the other five bitwise.
  Single-parameter inverse composition: `dz` 6.7e-18, `dx` 7.0e-19, `angle_x`
  6.1e-18, `angle_y` 6.1e-19, `angle_s` 2.7e-20, `t_offset` 0.0.
  **The compound case is LEAD U16-4.**
- **ref_tilt.** `SBend(L=2, angle=0.1, ref_tilt=π/2)` maps dispersion into `y`
  **bit for bit** equal to the untilted bend's `x` (difference 0.0), residual `x`
  = 6.1e-21, `z` bitwise equal — the vertical-bend claim. And the docstring's own
  stated test ("for a straight element it coincides exactly with `tilt`") holds
  **exactly**: `Quadrupole(ref_tilt=ψ)` equals `Quadrupole(tilt=ψ)` with
  difference **0.0** at ψ = 0.37, −1.1 and π/2.

### Symplecticity (ForwardDiff, exact — not finite difference)

`max|J'SJ − S|` at the standard probe point:

| element | residual |
|---|---|
| `Patch` (all 7 parameters nonzero, `:bmad`) | 2.220e-16 |
| `Patch` (all 7 parameters nonzero, `:madx`) | 2.220e-16 |
| `ChromaticityKick` (xi, beta, alpha, zeta, eta, R all nonzero) | 2.220e-16 |
| `ChromaticityKick` (plain) | 1.110e-16 |
| `ThinCrabCavity` (2 harmonics, both planes) | **0.0** |
| `SBend(L=2, angle=0.1, ref_tilt=0.37)` | 2.220e-16 |
| `ThinRFCavity` | see §3 table (≤ 4.44e-16) |

### The new `RefTilted` ctx path (F13, in the region diff)

`(elem::RefTilted)(ctx, particle_id, ...)` returns **bitwise** the same tuple as
the plain 6-argument call and as `track_particle(method, elem, ...)`, on an
`SBend(ref_tilt=0.37)`. Also verified over a *rolled `BeamLine`*: `RefTilted`
wrapping a `CompositeLine` (which has no `.method` field) works on all three
paths — `_inner_method(::CompositeLine)` is defined at `beam_line.jl:592`. Not a
defect; recorded because the plain-call path's `_inner_method(inner) = inner.method`
looks like it should fail there.

### Region diff items verified working

`ThinCrabCavitySpec(; frequency, N, ...)` and `LorentzBoostSpec(; angle, ...)` /
`RevLorentzBoostSpec(; angle, ...)` keyword round-trip forms build and compile
(U3-7 fix); `ChromaticityKick`'s `float(promote_type(...))` accepts the
all-integer flexible form (U12-5 fix, compiles to
`ChromaticityKick{Symplectic6DMap,Float64}`); `Patch(spec::ElementSpec{:patch})`
now rejects a wrong-kind spec with `MethodError` (U12-4 fix); the `voltage` +
explicit `beta0`/`gamma0` mix is refused (U12-3 fix); `_PLACEMENT_PARAMS` appear
in all six schemas.

---

## 6. Hypothesis (d) — examples/

### Execution log

Run verbatim from `<scratch>/audit/run/` (byte-identical copies, `src` symlinked,
so each script's `../result` lands in scratch). Invocation exactly as documented:
`julia --project=. examples/<name>.jl`.

| script | exit | wall | peak RSS | warnings/deprecations | files written |
|---|---|---|---|---|---|
| `knob_control.jl` | **0** | **33.4 s** | 1.66 GB | **0** | none (as its header promises) |
| `weak_strong_tracking.jl` | **0** | **39.5 s** | 1.78 GB | **0** | `weak_strong.lum`, `weak_strong_moments.h5` |
| `strong_strong_tracking.jl` | **0** | **53.7 s** | 2.65 GB | **0** | `pic_hcc.lum`, `pic_hcc.ele.h5`, `pic_hcc.pro.h5` |

(Wall times are cold-start, first-call-compile dominated, single process on this
host; the tracking itself is 2 turns at the small config defaults.)

**Reproducibility — bit-identical on re-run:**

```
weak_strong   rms = [9.570787996269571e-5, 1.1797688746010158e-4, 8.642069261157512e-6,
                     1.1634985550187557e-4, 6.013617230833779e-2, 6.584986899628289e-4]
strong_strong electron rms = [8.224897020012971e-5, 2.849005945081036e-4, 1.036419700534238e-5,
                              1.650738634926186e-4, 7.021209648524774e-3, 5.481470809149434e-4]
              proton   rms = [9.422779492815086e-5, 1.1989278847823692e-4, 8.148281847685992e-6,
                              1.2382658083667767e-4, 5.987801202592774e-2, 6.613387923224379e-4]
```
`diff` of the two runs' rms lines: identical for both scripts.

**Spot-checked physics (knob_control, printed values):**
`ele crab kick = 1.376276388216526e-3` = `tan(0.0125)/sqrt(150·0.55)` ✓;
proton harmonic ratio exactly −4 (4/3 : −1/3) ✓; `K = ±0.6165228113440198` =
`±1000·0.05/81.1` ✓; symbolic derivative 0.11012115191357792 vs finite difference
0.11012115178066217 (agreement 1.2e-9, as the 1e-9 step allows) ✓; reassigning
`ip.half_crossing_angle` recompiles the **same** task object (tracked `x[1]`
moves from 1.0000000172041585e-4 to 1.0000000247751249e-4) ✓; Symbolics adapter
active in script mode, round trip printed ✓.

### Header accuracy

| claim | verdict |
|---|---|
| `knob_control` run command, "no files are written" | accurate; scratch tree confirmed empty of output |
| `knob_control` two scenarios / knob mechanics description | accurate |
| `weak_strong` 4-step pattern, output names and meanings | accurate; both files produced |
| `weak_strong` cross-reference to `test/examples/weak_strong_tracking.jl` | present and correct |
| `strong_strong` 6-step pattern, output names | accurate; all three files produced |
| `strong_strong` "alternatives are shown commented below and share the same interface" | accurate — the commented block (168–179) sits **below** a plain `solver = PICPoissonSolver(...)` and every keyword checks out (this is the clean side of U18-1, which was about the *harness*, not the example) |
| `strong_strong` cross-reference to the harness | present and correct |

**One inaccuracy found:** `weak_strong`'s `input.total_turns` is dead and the
literal is duplicated — LEAD U16-7.

### AGENTS.md compliance

- **No environment variables.** `grep -n "ENV\[\|OCTOPUS_\|get(ENV" examples/*.jl`
  returns **nothing** in all three files. The rule holds.
- **Config block, not env toggles.** All three carry a small top-of-file
  `config` named tuple. ✓
- **Public APIs only.** U18's single exception (`Octopus._symbolics_adapter_active()`
  at `knob_control.jl:151`) is **fixed** in the region diff: the file now calls
  the exported `knob_symbolics_available()` (defined and exported at
  `src/knobs/symbolic.jl:2,58`). No internal (`Octopus._*`) call remains in any
  of the three files.
- **Top-of-file comment at the top.** One deviation — LEAD U16-11.
- **U18-3 (examples write into the repo tree) is UNCHANGED at HEAD.** Both
  tracking examples still default `result_dir = joinpath(@__DIR__, "..", "result")`,
  i.e. the repo root's gitignored `result/`, and the suite's examples testset runs
  them on every `Pkg.test`. Not re-raised as a new lead — it is U18-3, still open,
  and this unit's runs deliberately redirected around it.

---

## 7. Clean list (audited sound, with the evidence)

1. **`_rf_kick`'s map, everything except the documented boundary.** Symplectic to
   ≤ 4.44e-16 at three energies and two lengths; kick bitwise equal to the
   hand-built `qV·sin/(P0c)` TIME_ENERGY sandwich; `dδ/dp_t − 1/β = 0.0` exactly;
   zero voltage bitwise identity; transverse bitwise untouched; `L→0` linear in
   `L`; `ν_s ∝ √V`; the body genuinely carries no `β` factor. The two documented
   boundaries (no transit-time factor, no RF focusing) are honest and the third
   (velocity slip) is real, reproduced, and tracked.
2. **`ThinRFCavitySpec` argument validation.** Every one of the five documented
   error paths throws `ArgumentError` naming its fix, plus the new `voltage` +
   explicit `beta0`/`gamma0` refusal; unknown keys now warn and name the key.
3. **Lorentz boost pair.** Exactly invertible (≤ 3.4e-17 absolute, 4.8e-15
   relative worst case, over three angles and two amplitudes); identical to the
   published Hirata map to ≤ 5.4e-20; `ps` on the mass shell to 2.2e-16;
   `sec³`/`cos³` determinants exact; `angle = 0` bitwise identity; origin a
   bitwise fixed point; `x₁ = z tanφ` exact; `inverse_boost` involution holds.
   Half-angle convention consistent with every beam-beam call site in the repo.
4. **Crab cavity.** `|J'SJ − S| = 0.0` (exactly symplectic); all-zero strengths
   are the bitwise identity; `x`, `y`, `z` bitwise fixed by the kick; the
   documented map matches the code term for term; harmonic-tuple length and
   frequency validated in all three constructors; the keyword round-trip form
   added since `6a3f39ab` builds and compiles.
5. **Chromaticity kick.** Matches an **independent Hamiltonian-flow derivation
   bit for bit**; Courant-Snyder action preserved exactly; symplectic to
   2.22e-16 with every parameter nonzero; `xi = 0` is the bitwise identity;
   integer flexible form now promotes correctly (U12-5 fix confirmed); every
   declared parameter is read; `beta`/`alpha` accept 2- or 3-tuples and use only
   the transverse pair. (Its one defect is the Float32 kernel promotion, U16-8.)
6. **ref_tilt.** `ref_tilt = 0` returns the inner element unwrapped — identity by
   construction, verified bitwise; `ref_tilt = π/2` turns a horizontal bend into a
   vertical one with `y` bit-for-bit equal to the untilted `x`; the docstring's
   own "for a straight element it coincides exactly with `tilt`" test passes with
   difference **0.0** at three angles; the conjugation is symplectic to 2.22e-16;
   the new ctx-forwarding method (F13) is bitwise identical to the plain path,
   including over a rolled `BeamLine`.
7. **Patch, everything except the compound reference length and the rotation
   sense.** Symplectic to 2.22e-16 in both conventions with all seven parameters
   nonzero; the zero-parameter map is the **exact bitwise identity** at four
   probe points including the origin and all-negative coordinates; a pure-`dz`
   patch is the exact drift; a pure-`angle_s` patch is an exact rigid rotation;
   `t_offset` is exactly additive; all six single-parameter inverse compositions
   are identity to ≤ 6.7e-18; the wrong-kind-spec hole (U12-4) is closed.
8. **Examples.** All three run to completion, exit 0, **zero warnings**, numbers
   bit-reproducible across runs, run commands accurate, outputs as documented,
   **zero environment-variable reads**, and no internal-API call remains
   (U18's `_symbolics_adapter_active` is fixed). The commented solver
   alternatives in `strong_strong_tracking.jl` are correctly placed and their
   keywords check against the constructors.
9. **Region diff since `6a3f39ab`.** Every change in it was verified to do what
   it claims: the four F16 documentation blocks, the U12-2 phase-argument
   correction, the U12-3 refusal, the U12-4 signature tightening, the U12-5
   `float(promote_type(...))`, the U3-7 keyword forms for crab cavity and both
   boosts, the F13 `RefTilted` ctx method, `_PLACEMENT_PARAMS` in all six
   schemas, the `knob_symbolics_available()` swap, and the docstring/comment
   re-orderings (which fix the Julia 1.12 "interposed comment detaches the
   docstring" gotcha recorded in the 2026-08-05 audit — confirmed:
   `@doc ThinRFCavitySpec` and `@doc ThinRFCavity` both resolve).

---

## 8. Severity summary

| lead | severity guess | confidence | one line |
|---|---|---|---|
| U16-1 | Low | high | F16 correction cites §7; the ν_s criterion is §8, and §8 carries no marker |
| U16-2 | **Medium** | high | theory note §4/§9 still assert the `kz+φ` identity the element now disclaims |
| U16-3 | Low | high | the slip boundary is missing from `construction_help`/`element_help` |
| U16-4 | **Medium** | high | `_patch_reference_length` shifts the reference particle's z by `dz(cosθ−1)` |
| U16-5 | **Medium** | high | patch applies `W`, misalignments apply `Wᵀ` — the same angle is the opposite roll |
| U16-6 | Low | high | the registered patch example labels a vertical rotation "a crossing angle" |
| U16-7 | Low | high | `weak_strong`'s `input.total_turns` is dead; the literal is duplicated |
| U16-8 | Low | high | out-of-hypothesis: `TWOPI`/`0.5` promote a Float32 chromaticity kick to Float64 |
| U16-9 | Low | high | out-of-hypothesis seam: the SymplecticityContract tripwire sees exactly one kind |
| U16-10 | Low | med | half crossing angle named three different ways across the precedents |
| U16-11 | style | high | `using LinearAlgebra` above the top-of-file comment, and unnecessary |
