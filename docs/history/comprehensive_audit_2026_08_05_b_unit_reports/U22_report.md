# U22 Audit Report — coherent-mode Vlasov theory, benchmarks, and the theory note

Repo: `/cfs/ad/dxu/Library/Julia/Octopus` @ `b986c73` (read-only; **no repository file
was modified and nothing was written under `result/`** — every script was executed
through a symlink mirror in session scratch whose `result/` is a private directory,
verified by `@__DIR__` resolution before the first run).

Unit brief: close the coverage gap left by the halted 2026-08-05_b audit for the
coherent-mode region. Prior unit report: `U19_report.md` (read in full).

## Region — read line by line, in full

| file | lines |
|---|---|
| `validation/coherent_mode_vlasov_theory.jl` | 737 |
| `validation/coherent_beam_beam_modes.jl` | 215 |
| `validation/coherent_mode_eic_comparison.jl` | 175 |
| `validation/coherent_mode_scans.jl` | 114 |
| `validation/coherent_beam_beam_modes_beambeam3d.jl` | 68 |
| `docs/theory/coherent_beam_beam_modes.md` | 279 |

Also read: the `6a3f39ab..HEAD` diff over the region (the U19 fix campaign),
`AGENTS.md` §Hard-Won Rules and §Updating Validations,
`docs/comprehensive_audit.md` §Measured Lessons, `U19_report.md`,
`src/contracts/Contracts.jl:1451-1605` (`CoherentModePhysicsContract` docstring, struct,
`_coherent_mode_lambdas`, `validate`) and `test/runtests.jl:8185-8195` (its assertions),
`paper/README.md:30-46,160-190`, `paper/data/bb3d_decks/*`, `src/constants/Constants.jl`,
and the committed/`result/` TSVs the note quotes.

## Provenance — what was READ vs what was EXECUTED

Executed (all in scratch; logs kept beside this report):

1. `probe_u0_bands.jl` — LIB_ONLY include at production NJ=72/NPHI=128: `u(0)` for 11
   aspect ratios, the full `u(J)` profile, and the EIC coupled solve with the continuum
   bands computed three ways. Log: `probe_u0_bands.log`.
2. **Full run of `validation/coherent_mode_vlasov_theory.jl` at defaults** —
   405.6 s wall / 679 s CPU, rc=0. Log: `vlasov_full.log`; TSVs in `mirror/result/`.
3. `probe_independent_physics2.jl` + `probe_indep_scan.jl` — a **fully independent**
   reimplementation of the same 1D-reduced model (own Newton-Legendre nodes, `erfcx`
   from `SpecialFunctions`, own 400k-panel cumulative potential table, Gauss-Legendre
   angle rules, own assembly and eigen-solve) plus an independent Fourier derivation of
   the on-axis Gaussian field gradient. Logs: `probe_independent_physics2.log`,
   `probe_indep_scan.log`.
4. `probe_hermite_order.jl` — the script's own code with only the source-average
   quadrature order varied (96 → 4000 nodes), and the NJ dependence of `max u`.
   Log: `probe_hermite_order.log`.
5. `probe_Rgrid.jl` — the script's `raw_potential` against the independent `W(u)`.
6. `validation/coherent_beam_beam_modes_beambeam3d.jl` against the **committed**
   `paper/data/bb3d_decks/singleslice_fort.{24,25,34,35}`. Log: `bb3d_run.log`.
7. `validate(CoherentModePhysicsContract)` for `:pic`, `:gaussian_pic`, `:gaussian`.
   Log: `contract.log`.
8. **Full run of `validation/coherent_beam_beam_modes.jl` at defaults** (8192 turns,
   100k/beam, 3 solvers, `--threads=8`). Log: `cbb_full.log`.
9. **Full run of `validation/coherent_mode_scans.jl` at defaults** (`--threads=4`,
   **720 s wall** — above the protocol's 420 s cap, run with a longer cap rather than
   skipped), plus a thread-count reproducibility probe at 1/4/8 threads.
   Logs: `scans_full.log`, `probe_threads` output inline in this report.
10. `probe_selfcheck5_blindspot.jl` — a **scratch copy** of the theory script with
    `kernel_matrix` scaled by 1.05, to measure what self-check 5 does and does not see.

Runtime measurements for the long scripts in this region (this host, warm):
`coherent_mode_vlasov_theory.jl` **405.6 s wall / 679 s CPU** (168% — the eigen-solves
use threaded BLAS) against a header claim of "about 8-10 minutes warm (39 simulations)":
the simulation count is exactly right (9 aspect + 10 narrow + 20 box) and the time claim
is conservative on this host, so the U19-6 correction landed;
`coherent_mode_scans.jl` **720 s** at 4 threads (header claims 10-15 min — accurate);
`coherent_mode_eic_comparison.jl` **200 s** at 4 threads (header claims 4-8 min —
conservative); `coherent_beam_beam_modes.jl` at 8 threads is **far slower than its
header's "~10-20 min"**: the soft-Gaussian and PIC legs together took ≈ 30 min and the
GaussianPIC leg was killed by session teardown at ≈ 33 min without completing, so the
default three-solver run is ≥ 60 min on this host. Its first two legs are analysed
from their completed moment files in the Clean section; the GaussianPIC Λ is quoted from
the header and independently corroborated by the contract (1.1960/1.1965 at reduced
settings), not from my incomplete leg. Reported rather than silently omitted, per
protocol.

11. **Full run of `validation/coherent_mode_eic_comparison.jl` at defaults**
    (`--threads=4`, **200 s wall**, rc=0 — the header's "4-8 min" is conservative).
    Log: `eic_cmp.log`.
12. `probe_eic_corrected.jl` — the EIC coupled solve with the one broken component (the
    fixed-order source average) replaced by a panel rule that resolves `s_t`, everything
    else the script's own code; and `probe_eic_independent.jl` — the same asymmetric
    solve built from scratch. Together these settle U26-5.
13. `probe_referee_box.jl` / `probe_referee_box2.jl` — the script's particle referee at
    the box-converged setting (L=192, ngrid=32768) at all nine aspect ratios;
    `probe_cusp_split.jl` — whether the repair needs a cusp split (it does not);
    `probe_indep_conv.jl` — resolution convergence of the independent solve.

Every script in the region was executed at its documented defaults. Nothing in the
region was skipped.

---

## (b) Verdicts on the two suspected defects

### U26-4 — VERDICT: **REPRODUCED. The note is wrong; self-check 4 is right.**

`u(0)` as the code actually computes it (production NJ=72/NPHI=128, symmetric beams):

| r | `u(0)` at J=1e-6 | `u(J_min)` on the eigen-grid | exact `(1+r)/(1+√2 r)` | note §2 claim |
|---|---|---|---|---|
| 1.0 (round) | **0.83137** | **0.82965** | 0.82843 | 1 |
| 0.85 | 0.84514 | 0.84251 | 0.84011 | 1 |
| 0.7 | 0.86211 | 0.85886 | 0.85429 | 1 |
| 0.5 | 0.89664 | 0.89130 | 0.87868 | 1 |
| 5.0 | 0.74355 | 0.74267 | 0.74340 | 1 |
| 11.111 | 0.72478 | 0.72392 | 0.72463 | 1 |

`u(J)` is monotone decreasing (round beams: 0.8296 at J=0.0039 → 0.1129 at J=14.0), so
`max u = u(0) < 1` and the model's incoherent continuum is `[Q_0, Q_0 + ξ·u(0)]`
= `[Q_0, Q_0 + 0.83 ξ]` at r=1 — **not** `[Q_0, Q_0 + ξ]`.

I re-derived the target independently rather than trusting the script: the on-axis
linear field gradient of a 2D Gaussian of rms (a,b) is
`(1/2π)∫₀^{2π} cos²θ/(a²cos²θ+b²sin²θ)dθ = 1/(a(a+b))` (Fourier derivation; numerically
`4e-15` relative). The reduction's own source has widths (σ_src, s_t) = (1, √2 r) → its
gradient is `1/(1+√2 r)`; the physical normalizer that defines ξ uses the source's own
σ_y = r → `1/(1+r)`. The ratio is exactly `(1+r)/(1+√2 r)` — the script's `u0_exact`.

**Where the wrong claim lives:** `docs/theory/coherent_beam_beam_modes.md:64-67`
("`u(0)=1`, ... the incoherent continuum `[Q_0, Q_0+ξ]`") and — inside the very same
header that carries the correct self-check 4 —
`validation/coherent_mode_vlasov_theory.jl:25` ("`u_a(0) = 1`") and `:42`
("1. u(0) = 1 (normalization of the incoherent tune shift)"). Header item 1 and header
item 4 contradict each other 17 lines apart; item 1 also has no implementation (no
check anywhere tests `u(0)=1`, and none could pass).

### U26-5 — VERDICT: **half reproduced, half refuted.** The band edges ARE the artifact (back-solve exact to 4 digits), but the "none" conclusion for x **survives repair** — it does not reverse. Every *number* in §4's x row is wrong; the *conclusion* is right, and right for a different reason than the note gives.

Measured at NJ=72 (`probe_u0_bands.log`; identical to the full-run output):

| plane | witness aspect | max `u_e` | max `u_p` | band as coded | note §4 quotes |
|---|---|---|---|---|---|
| x | r_e=0.085, r_p=0.095 | **1.9825** | **2.4493** | e `[0.0800, 0.25488]`, p `[0.2280, 0.25094]` | e `[0.080, 0.2549]`, p `[0.228, 0.2509]` |
| y | r_e=10.59, r_p=11.84 | 0.7228 | 0.7248 | e `[0.1400, 0.21261]`, p `[0.2100, 0.21682]` | e `[0.140, 0.2126]`, p `[0.210, 0.2168]` |

The auditor's back-solve was right to four digits: 1.982 and 2.44 (measured 1.9825,
2.4493), both above the physical maximum of 1. Classification under the three bands:

| band definition | x plane: modes outside both | y plane: modes outside both |
|---|---|---|
| **as coded** (`ξ·max u`, `validation/coherent_mode_vlasov_theory.jl:703-704`) | none | **0.22432** |
| **physical** (`ξ·1`, the convention `coherent_mode_eic_comparison.jl:101-104,159-162` uses) | **0.25094 and 0.25488** | none |
| **model-exact** (`ξ·u(0)` with the converged `u(0)`, derived below) | **0.25094 and 0.25488** | none |

The third row is not a convention but a computation. Generalizing the symmetric identity
to unequal beams, the converged detuning maximum is
`u_a(0) = (σ_s + s_t/√2)/(σ_s + s_t)` (witness normalization cancels), giving for the
EIC x plane `u_e(0) = (95+9.014)/(95+12.748) = 0.9653` and
`u_p(0) = (106+9.014)/(106+12.748) = 0.9685` — so the code's 1.9825 and 2.4493 are
**too large by factors 2.05 and 2.53**, and the exact model bands are
e `[0.080, 0.16515]`, p `[0.228, 0.23707]`, i.e. within 2% of the physical band, not
twice as wide. The same formula reproduces the y plane's measured values to 0.1%
(predicted 0.7236 / 0.7254 vs measured 0.7228 / 0.7248), which is why the y row is
sound and the x row is not.

So under the note's own alternative convention the x conclusion would flip. **But that
mixture is illegitimate** — it combines eigenvalues computed from the broken `u(J)` with
a band computed from the correct one. To settle it I repaired the single broken
component (the fixed-order source average; `kernel_matrix` uses `raw_potential` and is
accurate — verified separately) and re-ran the same coupled solve with everything else
the script's own code:

| plane | quantity | as shipped | **repaired** | exact |
|---|---|---|---|---|
| x | max `u_e` | 1.9825 | **0.9632** | 0.9653 |
| x | max `u_p` | 2.4493 | **0.9672** | 0.9686 |
| x | e continuum | [0.0800, 0.2549] | **[0.0800, 0.1650]** | |
| x | p continuum | [0.2280, 0.2509] | **[0.2280, 0.2371]** | |
| x | top eigenvalue | 0.25488 | **0.23795** | |
| x | modes outside both | none | **none** | |
| y | max `u_e` / `u_p` | 0.7228 / 0.7248 | 0.7227 / 0.7248 | 0.7236 / 0.7254 |
| y | modes outside both | 0.22432 | **0.22432** | |

A **fully independent** asymmetric solve (own nodes, own `erfcx`, own potential, own
cross-kernel assembly, own eigen-solve — no code from the script) confirms the repaired
numbers to five digits:

| plane | max `u_e` | max `u_p` | e band | p band | top mode | outside both |
|---|---|---|---|---|---|---|
| x | 0.9626 | 0.9668 | [0.0800, 0.1649] | [0.2280, 0.2371] | **0.23795** | none |
| y | 0.7224 | 0.7248 | [0.1400, 0.2125] | [0.2100, 0.2168] | **0.22432** | **0.22432** |

so the script's cross kernels `K_ep`/`K_pe` are correct; only the detuning was wrong.

The repair also removes the NJ dependence that made the shipped bands "grid-dependent,
i.e. an artifact" in the first place:

| NJ | as-shipped max `u_e` / `u_p` (x) | repaired max `u_e` / `u_p` (x) | repaired top x eigenvalue |
|---|---|---|---|
| 40 | 1.130 / 1.775 | 0.9584 / 0.9641 | 0.23795 |
| 72 | 1.982 / 2.449 | 0.9632 / 0.9672 | 0.23795 |
| 120 | 2.203 / 2.624 | 0.9645 / 0.9680 | 0.23795 |
| exact | — | 0.9653 / 0.9686 | — |

The shipped `max u` diverges with NJ (a finer J grid reaches further into the broken
small-J region); the repaired one converges monotonically to the analytic limit, and the
top eigenvalue is identical to five digits at all three resolutions. The y plane is
stable at 0.22432 across all three, before and after repair.

**The answer to "which conclusion does the current code support":** "none detached in x"
is what both the shipped and the repaired solve give, so §4's x conclusion stands — but
every number supporting it changes, and its stated *reason* is wrong. After repair the
top x mode is 0.23795, sitting at the **proton** continuum edge
((Q−Q_p)/ξ_p = 1.06), not "at the e-continuum edge" with (Q−Q_e)/ξ_e = 1.98 — a ratio
that only ever meant "the electron band was inflated to twice its width". The y-plane
detached mode at 0.22432 is **unchanged by the repair** (its plane was already
converged), so the 2026-08-05 correction block's y-plane reversal is sound.

§4 nevertheless states two conventions without reconciling them: the theory table
(line 216-217) uses `ξ·max u`, the measurement table 26 lines later (line 242) uses
`[Q_e, Q_e+ξ_e] = [0.080, 0.168]`, and the companion script prints the latter.

Two further measurements sharpen this:

- The x-plane "top mode **at** the e-continuum edge, `(Q-Q_e)/ξ_e = 1.98`" is a
  **tautology**, not a finding: the band top is defined as `Q_e + ξ_e·max u`, and
  `max u` is attained at the smallest quadrature node, so the band top *equals* the
  largest diagonal entry of the matrix, `0.254876`, which the top eigenvalue
  (`0.254884`) reproduces to 8e-6. The statement cannot come out any other way.
- The x-plane witness aspect ratios are r ≈ 0.085/0.095, i.e. **inside the regime
  self-check 4 declares FAIL** and about which the script itself says values "must not
  be plotted or quoted" (`:516-519`). The whole x row of the §4 table is quoted from
  that regime with no cross-reference. (U19-3 said the same; still true at HEAD.)

Summary of the U26-5 verdict: the **numbers** in §4's x row are artifacts and must be
replaced (bands 2.06× and 2.53× too wide, top mode 0.25488 → 0.23795, the quoted
`(Q−Q_e)/ξ_e = 1.98` meaningless); the **conclusion** ("none detached in x") is
correct and survives repair; the **stated reason** ("top mode at the e-continuum edge")
is wrong — after repair the top x mode sits at the proton edge. The y row is sound in
numbers and conclusion (its plane is on the converged side, `u(0)` correct to 0.1%),
subject to U22-7, which shows the strong-strong run does not see the predicted mode.

---

## (a) Reference-provenance table — what is each comparison actually compared against?

| # | comparison | reference | independent of the subject? |
|---|---|---|---|
| 1 | self-check 4: `u(0)` vs `(1+r)/(1+√2 r)` (`:507`) | closed-form analytic; I re-derived it independently (Fourier, 4e-15) | **YES** — genuinely independent, and it binds (it is the check that caught the circular normalization) |
| 2 | self-check 5: harmonic Λ = 2 (`harmonic_Y`, `:342-379`) | closed form `K=-√(JJ')/2`, Λ=2 — a correct analytic reference | **NO, on the subject side.** `harmonic_Y` **re-implements** the assembly loop (`:351-364`) instead of calling `kernel_matrix` (`:235-254`); the comment at `:361` admits it ("Identical assembly constants to `kernel_matrix`"). The check validates a hand-copy: a 1.05× drift injected into `kernel_matrix` leaves self-check 5 at `Lambda = 1.999975 PASS`, kernel error 1.18e-14, while Y moves +2.2% (measured). See LEAD U22-4 |
| 3 | self-check 2 / sign selection: σ mode at `Q_0` (`:565-573`) | translation invariance — structural analytic property | **YES**, and it does bind on kernel *scale* (a mis-scaled kernel moves the σ mode) |
| 4 | `Y_1d_sim` particle referee vs `Y_m1_matrix` (`:407-481` vs `:261-301`) | a different solver of the same model (spectral Hilbert transform + macroparticles) | **Mostly.** Shares `erfcx_pos`; constructs an unused `PlaneKernel` at `:410`; and hand-copies the normalizer at `:415` instead of calling `analytic_gradient`. Both solvers divide by the *same* normalizer, so their agreement tests the kernel/solve, never the normalization — the script says so |
| 5 | note §3 "full 2D PIC (measured)" column | `coherent_mode_scans.jl`, i.e. the framework's own PIC solver | **NO** — it is the subject, correctly labelled as such (it is offered as "the physical answer", not as a check of the theory) |
| 6 | `coherent_beam_beam_modes.jl` Λ vs "Vlasov band 1.2-1.3" | literature (Yokoya & Koiso 1990; Herr & Pieloni) | **YES** (external), but stated only in prose — no assertion; see (f) |
| 7 | `coherent_beam_beam_modes_beambeam3d.jl` | **external code** BeamBeam3D output | **YES** — the only true cross-code reference in the region. But the "comparison" is `println` of a hardcoded literal (`:67-68`), so nothing connects the two numbers |
| 8 | `coherent_mode_eic_comparison.jl` theory bands (`:101-104,159-162`) | **a local re-derivation** of the theory band, `[Q, Q+ξ]`, which is **not what the referenced theory script computes** (`ξ·max u`) | **NO** — the overlay compares the PIC spectrum against band edges the theory code never produced. Not "a copy of itself", but a divergent local reimplementation of the reference. Its ξ values are also a hand-copy (`xi_pair`) of `xi_bb` |
| 9 | `CoherentModePhysicsContract` | mirrors `coherent_beam_beam_modes.jl` | **NO** by design; it is the executable form of the benchmark, gated against the literature band |

No case was found where a "reference" shares code with the thing under test in the
strict sense the sibling unit found. The two structural weaknesses here are #2 (the
*subject* is duplicated, so the analytic reference checks a copy) and #8 (the reference
is re-derived locally with a different formula than the code it claims to represent).

---

## (c) Table regeneration — cell by cell

I re-ran the generating computation in full (405.6 s wall) and diffed.

**All five TSVs are bit-identical** to the committed `result/` copies *and* to the
committed `paper/data/` copies:

```
yokoya_vs_aspect.tsv           IDENTICAL (fresh == result/ == paper/data/)
yokoya_vs_aspect_narrow.tsv    IDENTICAL
yokoya_box_convergence.tsv     IDENTICAL
yokoya_vs_xi_theory.tsv        IDENTICAL
eic_coherent_modes.tsv         IDENTICAL
```

**§3 table** (`docs/theory/coherent_beam_beam_modes.md:122-129`) vs the fresh run:

| row | note: matrix | fresh run | note: sim | fresh run | note: measured | committed measured TSV | cell verdict |
|---|---|---|---|---|---|---|---|
| 0.02 | 23.2 | 23.16447 | 1.297 | 1.29705 | 1.25 | 1.2522 (at r=0.05) | reproduces |
| 0.05 | 5.51 | 5.50531 | 1.289 | 1.28930 | — | — | reproduces |
| 0.1 | 1.923 | 1.92324 | 1.274 | 1.27357 | **1.27** | 1.2657 **at r=0.09** | reproduces; row label 0.1 vs measurement at 0.09 |
| 0.2 | 1.261 | 1.26061 | 1.246 | 1.24621 | 1.24 | 1.2373 | reproduces |
| 0.3 | 1.238 | 1.23806 | 1.223 | 1.22329 | — | — | reproduces |
| 0.5 | 1.206 | 1.20601 | 1.190 | 1.18992 | 1.20 | 1.2021 | reproduces |
| 0.7 | 1.184 | 1.18417 | 1.167 | 1.16741 | — | — | reproduces |
| 1.0 | 1.162 | 1.16195 | 1.143 | 1.14274 | **1.19** | 1.1884 | reproduces |
| (r=0.85) | *omitted* | 1.17187 / 1.15279 | | | | | row exists in the TSV, absent from the table |

**§4 table** (`:214-217`) vs the fresh run: every cell reproduces —
x: e `[0.080, 0.2549]`, p `[0.228, 0.2509]`, "none", top 0.25488, `(Q-Q_e)/ξ_e = 1.983`;
y: e `[0.140, 0.2126]`, p `[0.210, 0.2168]`, one mode 0.22432, ratios 0.840 / 1.523.

**No cell fails to reproduce.** The tables are honest transcriptions of what the code
prints. Every defect below is about what those numbers *mean*, or about prose around
them that the regeneration did not touch — with two exceptions where a *number in the
prose* is not produced by any run (U22-5, U22-6).

---

## (d) The physics, independently

**Rigid-dipole coherent modes, derived from scratch.** Two identical rigid Gaussians;
the coherent force depends on the separation Δ through the convolved distribution,
which has rms (√2 σ_x, √2 σ_y). Using the on-axis gradient `1/(a(a+b))` (derived above
by Fourier, not taken from the note):
`Λ_rigid = 2 · grad(√2σ_x, √2σ_y)/grad(σ_x, σ_y) = 2 · ½ = 1`, because the gradient is
**homogeneous of degree −2** in (a, b). Computed numerically at five aspect ratios:

```
round  1.00000000 | r=0.5  1.00000000 | r=0.09  1.00000000 | r=0.02  1.00000000 | sheet 1.00000000
```

σ mode: Δ ≡ 0 → no force → exactly `Q_0`. π mode: Δ = 2x̄ → shift = ξ.
This reproduces the note's §1 round-beam statement and **refutes its flat-beam
statement** (`:30-32`, `Y_rigid = 2/√2 = √2 ≈ 1.41`) — see LEAD U22-10.

**Finite-ξ map correction, derived independently.** One-turn matrix
`R(2πQ_0)·[[1,0],[-k,1]]`, `k = 4πY_0ξ/β` ⇒ `cos2πQ_π = cos2πQ_0 − 2πY_0ξ sin2πQ_0`
(the note's formula, confirmed), and `Y_eff = Y_0 − πY_0²ξ cot(2πQ_0)`. With
`cot(2π·0.31) = −0.3959` the correction is **positive**:

| ξ | my `Y_eff` | committed `yokoya_vs_xi_theory.tsv` | ΔY |
|---|---|---|---|
| 0.005 | 1.20939 | 1.2093862 | **+0.0094** |
| 0.010 | 1.21969 | 1.2196884 | +0.0197 |
| 0.020 | 1.24344 | 1.2434387 | **+0.0434** |

**Independent solve of the 1D-reduced model.** Fully independent implementation
(different node generator, different special-function source, different potential
quadrature, different angle rules), converged (two resolutions agree to 4 digits):

| r | independent Λ (NJ=64/96) | independent Λ (NJ=96/128) | script `Y_m1_matrix` | verdict |
|---|---|---|---|---|
| 0.02 | 1.3211 | 1.3208 | **23.1645** | script wrong by ×17.5 |
| 0.05 | 1.3083 | 1.3081 | **5.5053** | script wrong by ×4.2 |
| 0.1 | 1.2898 | 1.2897 | **1.9232** | script wrong by +49% |
| 0.2 | 1.2604 | 1.2604 | 1.2606 | **agrees to 1.6e-4** |
| 0.3 | 1.2380 | 1.2380 | 1.2381 | agrees |
| 0.5 | 1.2060 | 1.2060 | 1.2060 | agrees |
| 0.7 | 1.1842 | 1.1842 | 1.1842 | agrees |
| 0.85 | 1.1719 | 1.1719 | 1.1719 | agrees |
| 1.0 | 1.1620 | 1.1619 | 1.1620 | agrees |

For r ≥ 0.2 this is a **strong independent validation** of the kernel assembly, the
`1/(2π²)` projection, the `2ξe^{-J}w'` weighting, the normalization and the eigen-solve.
For r ≤ 0.1 it demonstrates the script's numbers are an implementation artifact and
recovers the true model curve — monotone 1.32 (flat) → 1.16 (round), i.e. inside the
literature band, not divergent. See LEAD U22-1.

**The published Yokoya factor.** For round equal beams the self-consistent
(Yokoya & Koiso 1990) π-mode shift is ≈ 1.21ξ; Herr & Pieloni (arXiv:1601.05235) quote
1.2-1.3 aspect-dependent. Four measurements at HEAD, three of them mutually
independent:

| estimate | Λ_x | Λ_y | source |
|---|---|---|---|
| BeamBeam3D (external code), 8192 turns | **1.197** | **1.210** | my run of the committed centroids (`bb3d_run.log`) |
| Octopus PIC, 8192 turns, 100k/beam | **1.1990** | **1.2064** | my full re-run of the benchmark at defaults this session (header claims 1.199/1.206 — exact) |
| Octopus soft-Gaussian, 8192 turns | 1.0963 | 1.1010 | same run (header claims 1.096/1.101 — exact) |
| Octopus GaussianPIC, 8192 turns | 1.200 | 1.207 | header value; my re-run of this leg was killed at ≈33 min before completing (see Unchecked) |
| `CoherentModePhysicsContract` (1024 turns, 20k) | 1.1753 | 1.1855 | `contract.log`, measured this session |
| soft-Gaussian (must fail) | 1.0979 | 1.0824 | `contract.log`, measured this session |

All PIC-family values sit within ≈ 2% of the published 1.21 and inside the repository's
declared band (1.12, 1.30); the moment closure lands at ≈ 1.09, below it, exactly as
documented. The Yokoya anchor **checks out**.

---

## (f) Every threshold in the region: ENFORCED or PRINT-ONLY

| # | file:line | threshold | status |
|---|---|---|---|
| 1 | `coherent_mode_vlasov_theory.jl:569` | `min(|σ drift|)/ξ ≤ 1e-4` → `error()` | **ENFORCED** (the only hard gate in the region; passes with 9× margin, measured 1.107e-5). Note it fires only if *both* signs fail, so a flipped kernel sign is absorbed by construction — documented honestly at `:555-564` |
| 2 | `:508` self-check 4 `|u(0)-u0_exact| < 2e-2` | PASS/FAIL print + `@warn` at `:516` | PRINT-ONLY (exit code 0 with 5 of 11 aspect ratios FAILing) |
| 3 | `:533-534` self-check 5 `|Λ-2| < 1e-3 && kernel_err < 1e-6` | PASS/FAIL print + `@warn` | PRINT-ONLY |
| 4 | `:546-552` σ-mode drift for both signs | printed, **no tolerance at all** | PRINT-ONLY (no threshold) |
| 5 | `:578-579` ξ-independence of Y | printed, **no tolerance at all** | PRINT-ONLY (no threshold) |
| 6 | `:618, :645` narrow/box `spread_percent` | printed + TSV | PRINT-ONLY (no threshold) |
| 7 | `:711-714` EIC `tol = 0.02·max(ξ)` in/out classification | printed + TSV columns | PRINT-ONLY |
| 8 | `coherent_beam_beam_modes.jl:194-196, 204-208` "Λ in 1.2-1.3" | prose expectation + printed Λ | PRINT-ONLY (zero assertions in the file; `:127` `ArgumentError` is input validation, not a physics gate) |
| 9 | `coherent_mode_scans.jl` (whole file) | none | PRINT-ONLY |
| 10 | `coherent_mode_eic_comparison.jl:167-168` band membership ±0.003 | printed booleans | PRINT-ONLY |
| 11 | `coherent_mode_eic_comparison.jl:126-135` decoherence time | printed + TSV | PRINT-ONLY |
| 12 | `coherent_beam_beam_modes_beambeam3d.jl:61-68` Λ vs the Octopus values | **hardcoded literal in a `println`** | PRINT-ONLY (no data path, no tolerance) |
| 13 | `Contracts.jl` `CoherentModePhysicsContract` `lambda_band=(1.12,1.30)`, `sigma_mode_atol=2e-4` | `passed` flag, asserted in `test/runtests.jl` | **ENFORCED** (the region's real gate, and it is outside the region) |

11 of 13 thresholds are print-only; the two enforced ones are the sign criterion and the
contract. Unchanged in kind from U19-4 — the U19 campaign converted the header prose to
say so honestly (`:33-39`) rather than adding gates, which is a defensible choice for a
characterization script, but it means **no threshold in this region can fail a run** and
the tables are only as good as the reader of the warning.

Two cheap invariants are missing, and between them they would have caught U26-5 **and**
the three bad symmetric rows mechanically, without any new physics:

- `max u ≤ 1` is exact in this model (`u_a(0) = (σ_s+s_t/√2)/(σ_s+s_t) ≤ 1`), yet nothing
  asserts it — and the EIC section computes its continuum edges *from* `max u`.
  `u(J)` must also be monotone decreasing, and where the quadrature has failed it is not:
  measured `false` for both beams in the EIC x plane and `true` for both in y, and
  `false` for the symmetric r ≤ 0.2 rows against `true` for r ≥ 0.5. (Monotonicity is the
  more conservative of the two — it also flags r = 0.2, whose Λ is in fact correct — so
  the per-row σ-drift criterion is the sharper tripwire and monotonicity the cheaper
  sanity bound.)
- `Λ − max u` distinguishes a detached mode from the band edge: measured 0.003-0.007 in
  the three broken rows versus 0.17-0.33 in every sound one. Reporting a Yokoya factor
  when that gap is at the eigenvalue-spacing level is reporting the continuum.
- A third is *already computed and already written to disk*: the
  `sigma_drift_over_xi` column of `yokoya_vs_aspect.tsv` is 0.180 / −3.1e-3 / −1.5e-4 at
  r = 0.02 / 0.05 / 0.1 against ≤ 3.3e-5 everywhere else, and the script's own 1e-4
  criterion is applied only at r = 1. Enforcing the existing criterion per row costs
  nothing and fails exactly the three rows that are wrong.

---

## Leads

### LEAD U22-1 [HIGH, confidence high] validation/coherent_mode_vlasov_theory.jl:108,111-112 (`GH_N/GH_W`, `gauss_avg`)
Claim: The flat-beam regime the note and the script disown as a limitation of the 1D
reduction is a **fixed-order quadrature bug**; the converged model values are
Λ ≈ 1.29-1.32, not 1.92-23.2, and note §3 conclusion 3 ("the 1D reduction itself fails
for flat beams ... the vertical degree of freedom is not a spectator") is refuted.
Mechanism: `gauss_avg` averages over the source Gaussian with a **fixed 96-node
Gauss-Hermite rule** (`const GH_N, GH_W = gauss_hermite(96)`), but the integrand
`_R(k,|x−x'|)` carries structure on the scale `s_t = √2 r`. The 96-node rule's innermost
nodes sit at |v| = 0.160 σ_src with spacing 0.320 σ_src, so the cusp region of width
`s_t` is unresolved once `s_t ≲ 0.3 σ_src`, i.e. r ≲ 0.2-0.3 — which **quantitatively
predicts the observed pass/fail boundary** (`s_t/σ_src` = 0.283 at r=0.2 and 0.424 at
r=0.3, both FAIL; 0.707 at r=0.5, PASS). With the cusp unresolved,
`averaged_potential`'s curvature at the origin is too large, and `u(J)` — the entire
diagonal of the eigenproblem — is wrong. It is not the R-grid: `raw_potential` agrees
with an independent `W(u)` to ≤ 4e-4 relative for u ≥ 1e-3. Raising **only** the Hermite
order in the script's own code converges `u(0)` monotonically toward the exact value
(r=0.1: 2.162 → 1.633 → 1.325 → 1.112 → 1.040 → 1.003 at 96/200/400/1000/2000/4000
nodes; exact 0.9637) — but *only* slowly: at r=0.05 even 4000 nodes still gives 1.252
against 0.9807. **Raising the order is not the fix.** What works, measured, is a rule
whose node *spacing* resolves `s_t`: a panel Gauss-Legendre rule over ±12σ_src gets
`u(0)` right to 0.3% at r=0.02 with only 100 panels × 10 nodes and to 0.1-0.3% with 400,
at comparable cost to the present 96 nodes. (I also checked whether forcing the source
point onto a panel boundary matters: it does not — 0.98921 vs 0.98977 at r=0.02 — so the
repair is purely about resolution, not about splitting.)
The file's own stated principle (`:126-129`, "every non-smooth piece is split off
analytically and only smooth remainders are integrated numerically") was followed —
`mean_abs` handles the `|u|` kink exactly — but *smooth* is not the same as *resolved*:
the remainder `R` is C², with all its structure inside `|x−x'| ≲ s_t`, and a
distribution-shaped rule with 0.32 σ_src spacing never looks there. Consequence: `yokoya_vs_aspect.tsv`
rows r ≤ 0.1, note §3 table rows 0.02-0.05 and 0.1, the † footnote's diagnosis, note
§3 conclusion 3, and the EIC x-plane bands (U26-5) all rest on this.
**What the §3 table should say** (drop-in for whoever fixes this; matrix column from the
independent converged solve, referee column from the script's own `simulate_1d_model` at
the box-converged setting L=192/ngrid=32768, measured column from the committed scan):

| r | 1D model, m=1 matrix (corrected) | 1D model, exact referee (L=192) | matrix vs referee | full 2D PIC | currently shipped matrix |
|---|---|---|---|---|---|
| 0.02 | 1.3207 | 1.3022 | 1.4% | — | 23.1645 |
| 0.05 | 1.3080 | 1.2992 | 0.7% | 1.2522 | 5.5053 |
| 0.10 | 1.2897 | 1.2820 | 0.6% | 1.2657 (r=0.09) | 1.9232 |
| 0.20 | 1.2604 | 1.2548 | 0.4% | 1.2373 | 1.2606 |
| 0.30 | 1.2380 | 1.2334 | 0.4% | — | 1.2381 |
| 0.50 | 1.2060 | 1.2033 | 0.2% | 1.2021 | 1.2060 |
| 0.70 | 1.1842 | 1.1818 | 0.2% | — | 1.1842 |
| 0.85 | 1.1719 | 1.1723 | 0.03% | — | 1.1719 |
| 1.00 | 1.1620 | 1.1605 | 0.1% | 1.1884 | 1.1620 |

The corrected model is monotone 1.32 (flat) → 1.16 (round), the m=1 truncation is
accurate to ≤ 1.4% at **every** aspect ratio in the shipped range, and the model tracks
the measured 2D curve within 2-4% except at round beams where it is 2% low. No regime in
the shipped table needs disowning. (Values at r = 0.02 and 0.05 are converged to 5
digits at NJ/NPHI up to 160/192: 1.32062 and 1.30800.)

Honest boundary of my own method, which is the mechanism restated: below r ≈ 0.02 my
panel rule stops resolving `s_t` too, and it fails the same way — at r = 0.01 it gives
`u(0)` = 1.008 (exact 0.996) and Λ = 7.16, at r = 0.005 `u(0)` = 11.9 and Λ = 44.8. Any
fixed rule has a flatness floor; the fix is to make the rule's spacing a function of
`s_t`, and to assert the invariants below rather than trusting a fixed order.

**A one-line tell that the shipped flat rows are not modes at all.** Re-running the
shipped code at NJ=100/NPHI=192 instead of 72/128:

| r | shipped Λ at 72/128 | Λ at 100/192 | `u(J_min)` at 100/192 |
|---|---|---|---|
| 0.02 | 23.1645 | 24.3279 | **24.3249** |
| 0.05 | 5.5053 | 5.9447 | **5.9427** |
| 0.10 | 1.9232 | 2.0389 | **2.0376** |
| 0.20 | 1.2606 | 1.2606 | 1.1172 |
| 0.50 | 1.2060 | 1.2060 | 0.8938 |
| 1.00 | 1.1620 | 1.1619 | 0.8305 |

For r ≤ 0.1 the reported "Yokoya factor" **equals `max u` to four digits** — the largest
eigenvalue is simply the top of the (spurious) continuum, i.e. there is no discrete mode
in the solution at all, and the quoted number is the band edge wearing a mode's name. It
also drifts with resolution, while for r ≥ 0.2 Λ is resolution-independent to 5 digits
and sits well above `max u`, as a genuine detached mode must. The gap
`Λ − max u` at the shipped resolution makes the split unmistakable:

```
r      0.02   0.05   0.10  | 0.20   0.30   0.50   0.70   0.85   1.00
gap    0.007  0.005  0.003 | 0.166  0.272  0.315  0.325  0.329  0.332
```

**And the script already writes the evidence into its own TSV.** The
`sigma_drift_over_xi` column of `yokoya_vs_aspect.tsv` — translation invariance, the
check the header calls "this validates every constant in the kernel at once" — reads
0.180, −3.14e-3, −1.54e-4 at r = 0.02, 0.05, 0.1 against ≤ 3.3e-5 at every r ≥ 0.2, and
the rigid-vector overlap collapses from 1.0000 to 0.5148 at r = 0.02. The script's own
1e-4 criterion is applied **only at r = 1** (as the sign selector); applying it per row
would have failed exactly the three bad rows and nothing else. Three one-line invariants
would each have caught this automatically: that per-row σ-drift criterion, `max u ≤ 1`
(exact in this model), and "if `Λ − max u` is at the eigenvalue-spacing level, report
*no discrete mode* rather than a Yokoya factor".

**Decisive cross-check — the script's own referee agrees with the corrected matrix.**
`simulate_1d_model` never calls `averaged_potential`, so it is untouched by this bug.
Run at the box-converged setting the script itself established (L=192, ngrid=32768):

| r | referee L=24 | referee **L=192** | independent matrix | agreement | script matrix |
|---|---|---|---|---|---|
| 0.02 | 1.2971 | **1.3022** | 1.3207 | 1.4% | 23.1645 |
| 0.05 | 1.2893 | **1.2992** | 1.3080 | 0.7% | 5.5053 |
| 0.10 | 1.2736 | **1.2820** | 1.2897 | 0.6% | 1.9232 |
| 0.20 | 1.2462 | **1.2548** | 1.2604 | 0.4% | 1.2606 |

Two solvers that share nothing but `erfcx` agree to 0.4-1.4% at every flat aspect ratio —
the same 1-2% agreement the note claims only for r ≳ 0.2 — while the shipped matrix
column is off by up to a factor 18. Note conclusion 2 therefore extends to r = 0.02, and
note conclusion 3 is false.

The refutation of conclusion 3 is direct: at r = 0.02 the converged matrix gives
Λ = 1.3208 with `u(0) = 0.9909`, i.e. a discrete π mode **well above** the continuum,
and the script's own particle referee — which is not affected by this bug — reports
1.2971 / 1.2893 / 1.2736 at r = 0.02 / 0.05 / 0.1 in its L=24 box (box-limited *low*,
per the script's own convergence study). Corrected matrix vs referee therefore agree to
1.8% / 1.5% / 1.2% at exactly the aspect ratios where the note says "the exact 1D-model
solution loses the discrete π mode", and the model sits within 2-5% of the measured 2D
PIC values (1.2522 at r=0.05, 1.2657 at r=0.09). The 1D reduction does not fail for flat
beams; the quadrature does.
The independent solve is itself converged in exactly the regime where the script
diverges — over a 2.7× resolution range (NJ/NPHI = 48/64 → 128/160) it moves by 1e-3:

| r | 48/64 | 64/96 | 96/128 | 128/160 | `u(J_min)` at 128/160 | exact `u(0)` |
|---|---|---|---|---|---|---|
| 0.02 | 1.3218 | 1.3211 | 1.3208 | 1.3207 | 0.99134 | 0.99194 |
| 0.05 | 1.3086 | 1.3083 | 1.3081 | 1.3080 | 0.98008 | 0.98066 |
| 0.10 | 1.2900 | 1.2898 | 1.2897 | 1.2897 | 0.96316 | 0.96371 |

Repro: `julia --project=. probe_indep_scan.jl` (independent solve) → Λ = 1.3208, 1.3081,
1.2897 at r = 0.02, 0.05, 0.1 vs the committed 23.1645, 5.5053, 1.9232, while agreeing
to 4 significant digits at r ≥ 0.2; `probe_indep_conv.jl` for the convergence table
above; and `probe_hermite_order.jl` for the u(0)-vs-Hermite-order table.

### LEAD U22-2 [MEDIUM-HIGH, confidence high] docs/theory/coherent_beam_beam_modes.md:64-67 and validation/coherent_mode_vlasov_theory.jl:25,42
Claim: The theory note and the script's own header state `u(0)=1` and an incoherent
continuum `[Q_0, Q_0+ξ]`; the code computes `u(0) = 0.8296` at r=1 and a continuum top
of `ξ·u(0)`. (U26-4.)
Mechanism: the 1D reduction convolves **both** beams' other-plane spreads into the kick
(`s_t = √2 r`) while ξ is defined by the source's own σ_y (= r), so the reduction's
small-amplitude detuning is smaller than ξ by exactly `(1+r)/(1+√2 r)` — 0.828 at r=1,
independently re-derived here from the on-axis gradient `1/(a(a+b))`. Self-check 4 tests
precisely this and is correct; header item 1 (`:42`) and the model description (`:25`)
were never updated when the circular normalization was removed, so the header asserts
both `u(0)=1` and "must be BELOW 1" 17 lines apart, and item 1 has no implementation.
Repro: `OCTOPUS_VLASOV_LIB_ONLY=1` include, then
`detuning_u(PlaneKernel(√2, ...), 1/(1+1), 1.0, 1.0, 1e-6)` → 0.83137 (exact 0.82843);
or read the shipped self-check-4 block of any full run (`vlasov_full.log`).

### LEAD U22-3 [MEDIUM-HIGH, confidence high] validation/coherent_mode_vlasov_theory.jl:703-704 and docs/theory/coherent_beam_beam_modes.md:214-217,242
Claim: Every number in §4's x row is a quadrature artifact — the continuum edges (max
`u_e` = 1.9825, `u_p` = 2.4493 at NJ=72, against the analytic 0.9653 / 0.9686), the top
mode (0.25488, repaired 0.23795) and the descriptive claim "at the e-continuum edge,
`(Q−Q_e)/ξ_e = 1.98`" (after repair the top mode sits at the **proton** edge). The row's
*conclusion* ("none detached") is the one thing that survives repair. (U26-5.)
Mechanism: `e_band = (Q_e, Q_e + ξ_e·maximum(res.u1))` takes the band top from the
largest diagonal entry, which is also (to 8e-6) the top eigenvalue, so "top mode at the
band edge" is tautological; and `max u` grows with NJ purely because a finer J grid
samples the diverging small-J region of the broken `u(J)` (NJ=40 → 1.130/1.775,
NJ=72 → 1.982/2.449, NJ=120 → 2.203/2.624). The x plane's witness aspect ratios
(0.085, 0.095) are inside the self-check-4 FAIL regime the script says must not be
quoted. Nothing asserts the exact invariant `max u ≤ 1`.
Repairing only the source average (`probe_eic_corrected.jl`, everything else the script's
own code) gives max `u_e`/`u_p` = 0.9632 / 0.9672 against the analytic
`(σ_s+s_t/√2)/(σ_s+s_t)` = 0.9653 / 0.9686, bands e `[0.080, 0.1650]`, p
`[0.228, 0.2371]`, top mode **0.23795** (NJ-independent at 40/72/120) and still "none
outside both". So the §4 x-plane *conclusion* survives; its bands, its top mode and its
stated reason do not — after repair the top x mode sits at the **proton** edge
((Q−Q_p)/ξ_p = 1.06), not the electron one.
Repro: `probe_u0_bands.jl` prints all band conventions and the modes outside each;
`probe_eic_corrected.jl` prints the repaired solve; or
`awk -F'\t' '$1=="x"' result/eic_coherent_modes.tsv | sort -k6 -g | tail -2` →
0.25094 (in_e=true) and 0.25488 (in_e=true, in_p=false), with
`(0.25488-0.08)/0.08821 = 1.982`.

### LEAD U22-4 [MEDIUM, confidence high] validation/coherent_mode_vlasov_theory.jl:342-364 vs :235-254
Claim: Self-check 5 — the check advertised as validating "every assembly constant ...
against a closed form" — tests a **hand-copy** of the assembly, not `kernel_matrix`.
Mechanism: `harmonic_Y` re-implements the φ/φ' grids, the accumulation and the
`(2π/nphi)(π/nphi2)/(2π²)` factor inline (`:348-362`) rather than calling
`kernel_matrix` with a harmonic potential; the comment at `:361` states the duplication
as if it were a guarantee. A drift in `kernel_matrix`'s projection factor or quadrature
weights would leave self-check 5 passing at Λ = 2.000 while every Λ in every table
scaled by the same wrong factor. This is Measured Lesson 4 (hand-copied knowledge
drifts) inside the check meant to prevent it. The σ-mode criterion (`:569`) does
partially cover the same failure — a mis-scaled kernel moves the σ mode — which is why
this is MEDIUM and not HIGH.
Repro (measured, not asserted): scale `kernel_matrix`'s result by 1.05 in a **scratch
copy** of the script and re-run the checks —
`self-check 5: Lambda = 1.999975  kernel_err = 1.18e-14 -> PASS` (both unchanged to all
printed digits), while Y silently moves 1.1620 → 1.1878 (+2.2%) and the σ-drift gate at
`:569` fires (|drift|/ξ = 0.0251 > 1e-4). So the injected assembly error is invisible to
the check advertised as covering it, and is caught only by a different check.
Parameterizing `kernel_matrix` by the pairwise potential would let self-check 5 exercise
the real path. Probe: `probe_selfcheck5_blindspot.jl`.

### LEAD U22-5 [MEDIUM, confidence high] docs/theory/coherent_beam_beam_modes.md:186-187
Claim: The finite-ξ map correction is quoted with the **wrong sign** — "(for Q_0 = 0.31:
ΔY ≈ −0.01 at ξ=0.005, −0.04 at ξ=0.02)" — contradicting the same note's line 171
("predicts a *positive* shift (+0.04)"), the committed `yokoya_vs_xi_theory.tsv`, and an
independent derivation.
Mechanism: `Y_eff = Y_0 − πY_0²ξ cot(2πQ_0)` and `cot(2π·0.31) = −0.3959 < 0`, so the
drift is positive at Q_0 = 0.31. The note's §3 discussion of the measured dip
("the correction predicts positive, the measurement dips by −0.036 ... with opposite
sign") is the correct reading; the parenthetical 11 lines later inverts it, which
destroys the point being made.
Repro: `awk -F'\t' '$1==0.005||$1==0.02' result/yokoya_vs_xi_theory.tsv` →
1.2093862 and 1.2434387 against the anchor Y_0 = 1.20, i.e. **+0.0094** and **+0.0434**.

### LEAD U22-6 [MEDIUM, confidence high] docs/theory/coherent_beam_beam_modes.md:131-140 (the † footnote)
Claim: The footnote that justifies flagging the r = 0.02-0.05 row quotes max-`u` numbers
that belong to a different computation and one of which no run produces.
Mechanism: it says "measured max u ≈ 1.8 at NJ=40 growing to ≈ 2.9 at NJ=72" for the
**symmetric** r=0.02-0.05 rows. Measured: symmetric r=0.02 gives max u = 11.83 (NJ=40)
and 23.16 (NJ=72); r=0.05 gives 2.82 and 5.50. The quoted 1.8 is the **EIC x-plane**
proton value at NJ=40 (measured 1.775 — U19-3's probe number), and 2.9 was an inference
in U19-3 from a mis-read flag: the top x eigenvalue is flagged inside the **electron**
continuum (`in_e=true, in_p=false`), which requires u_e = 1.982, not u_p ≈ 2.9 (measured
2.449). So the fix campaign imported a neighbouring lead's numbers into a footnote about
a different row.
Repro: `probe_hermite_order.jl` NJ block → `NJ=40 u_max(sym r=0.02)=11.826
u_max(sym r=0.05)=2.818 u_max(EIC x, e)=1.130 u_max(EIC x, p)=1.775`;
`NJ=72 → 23.158, 5.501, 1.982, 2.449`.

### LEAD U22-7 [MEDIUM, confidence high] docs/theory/coherent_beam_beam_modes.md:243 (and :233-256)
Claim: The §4 **comparison** table still states the retracted y-plane prediction ("top
coupled mode *at* the e-continuum edge — marginal") that the correction block 22 lines
above explicitly disowns; and the theory's one falsifiable EIC prediction — a discrete
y mode at 0.22432 — **is absent from the strong-strong measurement**, which the table
does not say.
Mechanism: the 2026-08-05 regeneration updated the theory table (`:214-217`), the
correction block (`:219-231`) and the comparison script's header, but not the
prediction column of the measurement table, so §4 asserts and denies the same claim.
Measured from the committed spectra: in [0.220, 0.229] the y-plane amplitudes are
8.5e-4 (e) and 1.2e-3 (p) of their global peaks — nothing there. The observed
persistent line is at 0.21094 ≈ the proton bare tune, which lies *inside* both
as-coded continua; the note's own prose says so, but the table's prediction/measurement
juxtaposition reads as confirmation of a prediction that failed.
Repro: peak scan of `result/eic_mode_spectra.tsv` (= `paper/data/eic_mode_spectra.tsv`):
global peaks at 0.09546 (e_x), 0.23096 (p_x), 0.21094 (e_y and p_y); max amplitude in
[0.220, 0.229] is 3.19e-06 (e_y) / 2.15e-05 (p_y) against global 3.75e-03 / 1.83e-02.
My own fresh run of the comparison script reproduces this independently: 2.92e-06 /
2.17e-05 in the same window against global 3.66e-03 / 1.80e-02 — 8e-4 and 1.2e-3 of the
peak. The predicted mode is not there in either dataset.

### LEAD U22-8 [LOW-MEDIUM, confidence high] validation/coherent_mode_vlasov_theory.jl:399-403,410
Claim: The referee's section comment states the **retracted** Fourier transform, and its
independence claim is overstated.
Mechanism: `:400` writes `FT[G](k) = -i pi sign(k) e^{-s^2 k^2 / 2}` — the Gaussian
suppression the note (`:106-110`) records as wrong and corrected on 2026-07-28 after
external review — while the code 21 lines later (`:421`) correctly uses the erfcx form,
with an inline comment (`:418-420`) explaining why the Gaussian form is wrong. The same
file therefore carries the error and its correction. `:402` "This shares NO code with
the matrix eigenproblem" is false (`erfcx_pos` is shared, and `:415` hand-copies
`analytic_gradient`'s formula), and `:410` constructs a `PlaneKernel` that is never used
(dead since the force became spectral). U19-9 raised the last two; all three survive at
HEAD.
Repro: read `:397-421`; `grep -n 'k\b' ` inside `simulate_1d_model` shows `k` used
nowhere after `:410`.

### LEAD U22-9 [LOW-MEDIUM, confidence high] validation/coherent_mode_vlasov_theory.jl:64-71
Claim: The header's "residual inconsistency" block describes a diagnostic the code no
longer computes and quotes values it no longer prints.
Mechanism: the header says the rigid-bunch diagnostic is
`2*normalized_equilibrium(k,√2)/normalized_equilibrium(k,1)` and "runs 1.21 (round) to
1.41 (extreme flat)". The code (`:498`) computes
`2*normalized_equilibrium(kk,√2)/n0phys` — divided by the *physical* normalizer — which
is **analytically exactly 1** (`2·[1/(√2(√2+s_t))]·(1+s_t/√2) = 1`) and measures 1.0085
(round) → 1.0000 (r=11.111). The body's own printed preamble (`:488-490`) says "The
rigid-bunch limit is analytically 1", directly contradicting the header. The header then
draws a conclusion from the stale number ("the reduction is therefore not a quantitative
instrument at the few-percent level; see the manuscript's Sec. 5.1"), which now rests on
nothing in this file. **Cross-file seam, not followed:** whether `paper/` Sec. 5.1 still
quotes 1.21/1.41 is outside my region.
Repro: any full run — the self-check-4 block prints `rigid=1.0085` at r=1 and
`rigid=1.0` at r=11.111, never 1.21 or 1.41.

### LEAD U22-10 [LOW, confidence high] docs/theory/coherent_beam_beam_modes.md:30-32
Claim: "For flat beams the gradient scales as 1/σ_x (sheet-like field), so the same
argument gives Y_rigid = 2/√2 = √2 ≈ 1.41" is wrong; the rigid Yokoya factor is exactly
1 at **every** aspect ratio. (Out of hypothesis.)
Mechanism: the linear on-axis gradient of a 2D Gaussian is `1/(σ_x(σ_x+σ_y))`, which is
homogeneous of degree −2, so widening *both* rms sizes by √2 in the convolution halves
it regardless of flatness, and the factor-2 relative displacement restores exactly 1.
The quoted "1/σ_x" scaling is dimensionally impossible for a 2D field gradient. The
error is not cosmetic: with Y_rigid = 1.41 for flat beams, the repository's own measured
flat-beam values (1.2522 at r=0.05, 1.2657 at r=0.09) would sit **below** the rigid
model, inverting the framing that the whole benchmark rests on ("rigid models
underestimate; the self-consistent value is 1.2-1.3"). With the correct Y_rigid = 1 the
measured values sit above it at every aspect ratio, as they must. §1 also contradicts
`validation/coherent_beam_beam_modes.jl:10` ("A rigid-bunch model gives Lambda = 1") and
`validation/README.md:600` ("rigid = 1"), both of which are correct.
Repro: `probe_independent_physics2.jl` part (B) → Λ_rigid = 1.00000000 at
r = 1, 0.5, 0.09, 0.02 and in the sheet limit, with the θ-integral form of the gradient
matching `1/(a(a+b))` to 4e-15.

### LEAD U22-11 [LOW, confidence high] region-wide (see the table in §(f))
Claim: 11 of the 13 thresholds in this region are print-only; no run in the region can
fail on physics, and the one invariant that would have caught U26-5 mechanically
(`max u ≤ 1`) is not asserted anywhere.
Mechanism: as enumerated. Two notes beyond U19-4. (i) The single enforced gate
(`:569`) is evaluated only at r=1 and only fails if *both* kernel signs are wrong, so it
cannot catch a sign flip — honestly documented. (ii) In the **symmetric** case
`Y` is sign-invariant: `M = [[A,C],[C,A]]` has eigenvalues `A±C`, so flipping
`sign_kernel` swaps the σ/π labels but leaves `maximum(eigvals)` unchanged — confirmed
by the shipped output, where both signs report `Y = 1.162` while the σ drift moves from
1.1e-5 to 1.16. The gate therefore protects the σ/π *interpretation* and the EIC
section, not the symmetric tables' numbers.
Repro: `grep -n 'error(\|@assert\|exit(' validation/coherent_*.jl` → one hit
(`coherent_mode_vlasov_theory.jl:569`); the full-run log shows five self-check-4 FAILs
and `rc=0`.

### LEAD U22-12 [LOW, confidence high] validation/coherent_beam_beam_modes_beambeam3d.jl:8-30,67-68
Claim: The cross-code comparison **data** is committed and reproduces exactly, but its
**provenance** is not: no BeamBeam3D version, no run date/host/operator, and no
committed note linking `singleslice_fort.*` to the deck beside it. (Answers (e).)
Mechanism: `paper/data/bb3d_decks/singleslice_fort.{24,25,34,35}` and `beam1.in`/
`beam2.in` are tracked (committed at `3722fbd`, 2026-07-28) and I verified they are
bit-identical to the external run directory `/cfs/ad/dxu/Library/BeamBeam3D/coherent_modes`
on this host. The deck matches the Octopus benchmark parameter by parameter (100k
macroparticles, 128×128, 1 slice, 8192 turns, σ=106 µm, β*=0.55, npart 8.9141e9, tunes
62.31/60.32, cn.x = 1.06e-5 = 0.1σ). But: the BeamBeam3D checkout is at commit
`50d01d8`, recorded nowhere in this repository; `BeamBeam3D.log` (which would date the
run) is not committed; `paper/README.md:34` says only "the deck in `data/bb3d_decks/`"
without naming which of the six decks; and the script's default `rundir` is still the
uncommitted host path (U19-7, unchanged). The sibling `multislice_nooffset/README.txt`
shows the standard this archive can meet — it names the deck, the run length, the
mpirun command and the analysis script — so the gap is an omission, not a convention.
Also `:67-68` prints the Octopus numbers as a **string literal**, so nothing detects
drift between the two codes.
Repro: `cp paper/data/bb3d_decks/singleslice_fort.24 $D/fort.24` (and 25/34/35), then
`julia --project=. validation/coherent_beam_beam_modes_beambeam3d.jl $D` →
`x (8192 turns): Q_sigma=0.310001 (drift 1.5e-6) Q_pi=0.315989 Lambda=1.197`,
`y: Q_sigma=0.319996 (drift -3.8e-6) Q_pi=0.326045 Lambda=1.21`.

### LEAD U22-13 [INFO, confidence high] docs/theory/coherent_beam_beam_modes.md:118-120,211-212,167
Claim: The figures the regenerated sections point at predate the data they claim to
show, and are not committed.
Mechanism: `result/yokoya_vs_aspect.png`, `result/yokoya_vs_xi.png` and
`result/eic_coherent_modes.png` are all dated 2026-07-27 21:29, while the TSVs the note
calls "regenerated 2026-08-05" are dated 2026-08-05 14:07-14:12. On this host the
figures therefore still draw the pre-fix curve (the 0.86-1.40 matrix column the §3 text
now disowns); `result/` is gitignored, so a fresh clone has no figure at all. The
committed `paper/data/*.tsv` are post-fix and match current code exactly, so this is a
note-to-figure link problem, not a paper-data problem. **Seam, not followed:** whether
`paper/figs/fig_yokoya_scans.pdf` (committed 2026-07-29 at `467548b`) shows the current
curve is outside my region.
Repro: `ls -l --time-style=+%F_%R result/yokoya_vs_aspect.{png,tsv}`.

### LEAD U22-14 [INFO, confidence high] docs/theory/coherent_beam_beam_modes.md:167,177,122-129
Claim: Presentation defects in §3 that make the section hard to read correctly: the
heading "**$Y$ versus $\xi$**" appears twice (`:167` and `:177`) introducing two
different discussions of the same quantity, the second of which contains the sign error
of U22-5; the r=0.85 row of `yokoya_vs_aspect.tsv` is silently absent from the table;
and the row labelled "0.1" carries a measured value taken at r=0.09. Also `:147-150`,
"the EIC-like aspect r=0.09 point re-measured at 4x turns and 2.5x macroparticles
reproduces Y = 1.266 **exactly**" — the re-measurement
(`paper/data/lambda_flat_converged.tsv`) is three seeds at 1.2713 / 1.2673 / 1.2617,
mean 1.2668 with a 0.0096 spread, against the scan's 1.2657: agreement well **inside**
the seed scatter, which is the honest claim; "exactly" is not.
And in the script, `validation/coherent_mode_vlasov_theory.jl:735`: the closing summary
still names 3 of the 5 TSVs the run writes (missing `yokoya_vs_aspect_narrow.tsv` and
`yokoya_box_convergence.tsv`), which the header at `:73-74` lists correctly — U19-6,
unchanged.
Repro: read `:116-190` against `result/yokoya_vs_aspect{,_measured}.tsv` and
`paper/data/lambda_{flat,round}_converged.tsv`; and compare the run's last line with
`ls mirror/result/`.

### LEAD U22-15 [INFO, confidence high] validation/coherent_mode_vlasov_theory.jl:678-680,415; validation/coherent_mode_eic_comparison.jl:57-67
Claim: Hand-copied constants and formulas across the region (Measured Lesson 4), all
currently harmless.
Mechanism: (i) the theory script hardcodes `RE_M = 2.8179403262e-15`,
`EMASS = 0.51099906e6`, `PMASS = 938.27231e6`, while the framework carries
`RE = 2.8179403205e-15`, `EMASS_EV = 0.51099895069e6`, `PMASS_EV = 938.27208943e6`
(older CODATA), so the two scripts that are supposed to describe the same EIC case use
different constants — the resulting ξ differ by ≈ 2e-7 relative, invisible at the
quoted 4 digits; (ii) `simulate_1d_model:415` re-derives the normalizer inline instead
of calling `analytic_gradient`; (iii) `coherent_mode_eic_comparison.jl:62-67`
(`xi_pair`) is a hand-copy of the theory script's `xi_bb`, and `xi_of` (`:57-59`) is
dead code (U19-9, unchanged); (iv) `coherent_beam_beam_modes_beambeam3d.jl:68` hardcodes
the Octopus Λ values.
Repro: `grep -n 'const RE_M\|const EMASS\|const PMASS' validation/coherent_mode_vlasov_theory.jl`
against `src/constants/Constants.jl:11-20`.

### LEAD U22-16 [INFO, confidence med] validation/coherent_mode_vlasov_theory.jl:508
Claim: Self-check 4's 2e-2 tolerance passes at r=0.5 with only 11% of its budget to
spare, so the boundary of the "validated regime" quoted throughout the note
(r ≥ 0.5 trustworthy, r ≤ 0.3 not) is one quadrature change away from moving.
Mechanism: measured |u(0) − u0_exact| = |0.89664 − 0.87868| = 0.01796 at r=0.5 against a
2e-2 tolerance (r=0.3 fails at 0.0694, r=0.7 passes at 0.0078). The failure is smooth in
r, so the pass/fail boundary is a property of the tolerance, not of the physics; if
U22-1 is fixed the whole range passes and the "validated regime" language becomes
unnecessary.
Repro: the self-check-4 block of any full run (`vlasov_full.log:9-20`).

### LEAD U22-17 [LOW, confidence high] validation/coherent_mode_scans.jl and validation/coherent_mode_eic_comparison.jl — SEAM (cause outside my region)
Claim: The committed strong-strong archives **no longer reproduce** from current code
wherever the spectral line is broad, although neither generating script has changed. For
the aspect scan the deviation grows monotonically with flatness and is deterministic;
for the EIC comparison the *quoted peak location* moves.
Mechanism: a full default run of `coherent_mode_scans.jl` at HEAD (720 s wall) gives

| r | archived (2026-07-27) | fresh at HEAD | Δ |
|---|---|---|---|
| 0.05 | 1.252191242179701 | 1.2531805553776199 | **+9.9e-4** |
| 0.09 | 1.2657142744011751 | 1.2656574196689974 | −5.7e-5 |
| 0.2 | 1.237255015489136 | 1.237255008753002 | −6.7e-9 |
| 0.5 | 1.2021090599688034 | **bit-identical** | 0 |
| 1.0 | 1.1883888442914992 | **bit-identical** | 0 |

and the ξ scan reproduces bit-identically except ξ=0.02 (Δ = 8.5e-13). It is **not**
thread nondeterminism: I re-ran r = 0.05, 0.09, 1.0 at 1, 4 and 8 threads and all three
give the identical 16-digit values above.

The same effect, more visibly, in the EIC comparison: a fresh default run reproduces the
committed decoherence times exactly (48 / 112 / ∞ / ∞) and the y-plane and proton-x peak
locations exactly (0.21094, 0.23096), but the **electron x peak moves from 0.09546 to
0.10571** — because that line is broad and carries three near-degenerate maxima
(archive: 2.860e-4 at 0.09546, 2.513e-4 at 0.10596, 2.517e-4 at 0.11938), so `argmax`
flips under any perturbation. The note quotes "e peak 0.0955" (`:242`) as a measurement;
it is one of three, and the run at HEAD picks a different one. The physics claim it
supports ("confined to the e band [0.080, 0.168], broad, Landau-damped") is unaffected —
0.10571 is inside the same band — but the specific number is not reproducible and should
be quoted as a band or a centroid, not a peak. `coherent_mode_scans.jl` is untouched by the
U19 fix campaign (`git diff 6a3f39ab HEAD` shows no change), so the perturbation entered
from outside the region — 118 commits touched `src/` since the archive was taken;
`fc803de` ("lost particles leave every reduction"), `f65aaf2` ("stop computing a
symmetric matrix twice") and `a5d8609` (RNG hygiene sweep) are the visible candidates.
The flat cases amplify an otherwise ULP-level perturbation because their spectral lines
are broad: ΔΛ = 9.9e-4 at ξ=0.005 is ΔQ_π = 5e-6, i.e. 1% of an FFT bin at 2048 turns.
**Every number the note quotes survives at its quoted precision** (1.25, "1.266", 1.24,
1.20, 1.19), so this is provenance, not physics. Per protocol I stop here: identifying
the commit is the auditor's job.
Repro: `julia --threads=8 --project=. validation/coherent_mode_scans.jl` (redirect
`result/`), then `diff result/yokoya_vs_aspect_measured.tsv paper/data/yokoya_vs_aspect_measured.tsv`.

### LEAD U22-18 [INFO, confidence high] validation/coherent_mode_vlasov_theory.jl:718
Claim: Latent crash — `maximum(v for v in vals if v <= e_band[2] + 5 * xi_e)` throws
`ArgumentError: reducing over an empty collection` if no eigenvalue lies below the
electron band top plus 5 ξ_e.
Mechanism: the generator is unguarded. It cannot fire for the two shipped EIC planes
(the lowest eigenvalue is always near Q_e), but the line is one parameter change — a
much larger tune split, or an inverted band ordering in a future asymmetric case — away
from aborting the run *after* the TSV has been partially written. Out of hypothesis;
robustness only.
Repro: structural; `vals` is `sort(real.(res.values))` and the filter has no fallback.

---

## Clean — verified sound, with the evidence

1. **The tables regenerate exactly.** A full default run (405.6 s wall, rc=0) produced
   `yokoya_vs_aspect.tsv`, `yokoya_vs_aspect_narrow.tsv`, `yokoya_box_convergence.tsv`,
   `yokoya_vs_xi_theory.tsv` and `eic_coherent_modes.tsv` **bit-identical** to both the
   `result/` copies and the committed `paper/data/` copies. Every cell of note §3 and §4
   reproduces (table above). The 2026-08-05 regeneration claim is true.
2. **The kernel assembly and eigen-solve are independently confirmed** for r ≥ 0.2: a
   from-scratch reimplementation (different quadrature generator, `SpecialFunctions.erfcx`,
   different potential table, Gauss-Legendre angle rules) reproduces `Y_m1_matrix` to
   ≤ 2e-4 relative at r = 0.2, 0.3, 0.5, 0.7, 0.85, 1.0, and is itself converged
   (NJ=64/NPHI=96 vs NJ=96/NPHI=128 agree to 4 digits). **The narrow-plane branch that
   the paper quotes is confirmed too** — independent 1.1394 / 1.1099 / 1.0956 / 1.0824
   at r = 1.5 / 3 / 5 / 11.111 against the shipped 1.1394 / 1.1099 / 1.0956 / 1.0824 —
   and the asymmetric cross kernels are confirmed by an independent EIC solve agreeing
   to five digits on both planes. My independent assembly passes the same harmonic
   closed-form test the script uses (kernel error 1.3e-14, Λ = 1.999988), so the
   agreement is not two implementations sharing one mistake. Honest caveat: the single
   most extreme narrow row, r = 500, differs by 0.7% (independent 1.0780 vs shipped
   1.0708). I traced that one to **my** implementation, not the script's: at r=500 the
   whole calculation lives in the first 30 entries of my cumulative-potential table,
   where my cubic interpolation uses a clamped stencil, and my `u(0)` is 0.7144 against
   the exact 0.7075 independently of panel count. The script's value is the trustworthy
   one there. Every other row of the narrow branch agrees to ≤ 0.03%.
3. **Self-check 5's numerics are excellent** where they apply: assembled kernel vs the
   closed form `-√(JJ')/2` max relative error **1.18e-14**, `q_σ - Q_0 = 1.25e-7`,
   `(q_π-Q_0)/ξ = 1.999988`, Λ = 1.999975 — it would bind hard on a constant regression
   in its own copy (see U22-4 for the copy problem).
4. **Self-check 4's analytic target is correct**, re-derived here from first principles
   (Fourier form of the on-axis gradient, verified to 4e-15), and the check genuinely
   binds on the converged side. Extending it beyond the 11 sampled aspect ratios to
   every row of the narrow branch, the shipped `u(0)` matches
   `(1+r)/(1+√2 r)` to ≤ 1.5e-3 relative at r = 1.5, 2, 3, 5, 11.111, 20, 50, 100 **and
   500** — the whole r ≥ 1 side is sound, not just the two points the check samples
   there.
5. **Translation invariance holds:** σ-mode drift/ξ = −1.107e-5 at r=1 with rigid-vector
   overlap 1.000; the enforced gate passes with 9× margin, and the opposite sign is
   rejected at 1.16.
5b. **The action-domain truncation `JMAX = 14` is adequate:** independently varying it
   over 10 / 14 / 20 / 28 moves Λ by 2e-5 (1.16193 → 1.16196). The hardcoded constant is
   not a hidden knob.
6. **ξ-independence holds** — and more sharply than the script prints: the shipped check
   reports Y(ξ) = Y(2ξ) = 1.162 at 3 digits, and the independent solve gives
   Λ = 1.16195 at ξ = 0.005, 0.01, 0.02 *and* at Q_0 = 0.22 instead of 0.31, i.e.
   independent of both to 6 digits, as the leading-order construction requires.
7. **Box convergence is real, and the narrow branch's 7.5-12.6% "spread" is entirely
   the box:** the m=1/particle spread falls monotonically to 0.12% (r=1) and 0.03%
   (r=11.111) as L goes 24 → 192 at fixed dx, which I reproduced; and running the referee
   at L=192 across the narrow branch gives 1.1398 / 1.1101 / 1.0985 / 1.0826 at
   r = 1.5 / 3 / 5 / 11.111 against the matrix's 1.1394 / 1.1099 / 1.0956 / 1.0824 —
   0.03-0.3%, versus the 2.2-7.5% the shipped L=24 column shows. The note's claim that
   the apparent truncation error is a box artifact is correct at every aspect ratio.
8. **The finite-ξ map algebra is correct** (independently derived) and the committed
   `yokoya_vs_xi_theory.tsv` matches it to 5 decimals — only the note's parenthetical
   sign is wrong (U22-5).
9. **The cross-code anchor reproduces:** the committed BeamBeam3D centroids give
   Λ = 1.197 (x) / 1.210 (y) with σ-mode drift 1.5e-6 / −3.8e-6 through the script's own
   estimator, matching the value quoted in the note, the README and the contract
   docstring; the committed deck matches the Octopus configuration parameter by parameter.
9b. **The benchmark's headline numbers reproduce exactly at HEAD.** A fresh full run of
    `coherent_beam_beam_modes.jl` at defaults (8192 turns, 100k/beam) gives, through the
    script's own estimator on its own moment files: soft-Gaussian Λ = **1.0963 / 1.1010**
    against the header's 1.096/1.101, and PIC Λ = **1.1990 / 1.2064** against the
    header's 1.199/1.206 — exact at the quoted precision. The header's "sigma mode at the
    bare tune to < 4e-6 in all runs" also holds: measured drifts 1.78e-6 / −3.42e-6
    (soft-Gaussian) and 1.80e-6 / −3.48e-6 (PIC). Note the contrast with U22-17: the
    round-beam benchmark is perfectly reproducible while the flat-beam scan is not, which
    is consistent with the sharp-line/broad-line explanation.
10. **The contract gates real physics and runs green:** PIC 1.1753/1.1855 and
    GaussianPIC 1.1960/1.1965 inside (1.12, 1.30); soft-Gaussian 1.0979/1.0824 fails as
    documented; worst σ drift 5.2e-5 against a 2e-4 tolerance.
11. **The published Yokoya anchor checks out:** four estimates (external BeamBeam3D,
    Octopus PIC, Octopus GaussianPIC, contract) land in 1.175-1.210 against the
    literature's ≈ 1.21 for round beams, with the rigid value 1 and the moment closure
    1.09 correctly below.
12. **The note's §4 measurement row is accurate**, and I re-ran the script that produces
    it (200 s, rc=0): decoherence 48 / 112 / ∞ / ∞ turns reproduces **bit-identically**,
    the y-plane line sits at 0.21094 in both beams and the proton x peak at 0.23096 in
    both the archive and the fresh run, and the y line stands ~4 decades above the
    spectrum median (the note's "two decades" is conservative). The one number that does
    not reproduce is the broad electron-x peak (U22-17), and it stays inside the same
    band.
13. **The two closed forms at the heart of the model are correct** (re-derived here,
    not taken from the note): the v-averaged kick
    `G(u) = <u/(u²+v²)>_{v~N(0,s)} = sign(u)√(π/2)/s · erfcx(|u|/(√2 s))` follows from
    `∫₀^∞ e^{-p²x²}/(x²+a²)dx = (π/2a)e^{a²p²}erfc(ap)`; and its Fourier transform
    `-iπ sign(k) e^{s²k²/2} erfc(s|k|/√2)` follows from
    `FT[u/(u²+v²)] = -iπ sign(k) e^{-|k||v|}` averaged over the half-normal. The note's
    §2 statement of both is right, and the referee's `Ghat` (`:421`) implements the
    correct one — only the section comment at `:400` still shows the retracted form
    (U22-8).
14. **No circularity against the framework:** the Vlasov script never loads Octopus —
    own quadratures, own `erfcx`, own eigen-solve; the EIC constants are re-entered
    independently.
15. **The measured 2D scans reproduce where the note leans on them hardest:** a fresh
    full run of `coherent_mode_scans.jl` gives bit-identical Λ at r = 0.5 and r = 1.0 and
    at three of the four ξ points, and reproduces r = 0.2 to 7e-9; only the two flattest
    rows drift (U22-17), and never enough to change a quoted digit. Runs are also
    thread-count invariant here: identical 16-digit output at 1, 4 and 8 threads.
16. **Hygiene:** every script seeds the global RNG explicitly (`set_global_rng!` with an
    explicit seed at the top of each Octopus-dependent script);
    `coherent_beam_beam_modes.jl` reseeds per solver case (`run_case:131`) so the three
    solvers see identical beams and case order does not matter; every output goes under
    `result/` (gitignored), and my full runs wrote nothing outside the scratch mirror.
    One AGENTS.md tension survives in my region and is unchanged from U19-8:
    `coherent_mode_eic_comparison.jl:138` writes the dense 204 KB per-frequency
    `eic_mode_spectra.tsv` by default, against "avoid writing dense per-case data by
    default" — defensible, since the overlay figure consumes it and `paper/data/` archives
    the same file.

## Unchecked, and why

- Nothing in the region was left unexecuted: all five scripts ran at their documented
  defaults, plus the contract and eleven probes. The one **incomplete** run is the
  GaussianPIC leg of `coherent_beam_beam_modes.jl`, which ran ≈ 33 minutes and was then
  killed by session teardown without writing its moment files (measured partial runtime
  reported above rather than omitted); its
  two sibling legs completed and reproduce the header exactly, and the contract covers
  the same solver at reduced settings.
- The benchmark header's runtime claim ("~10-20 min at defaults") is understated by
  roughly 3× on this host — a documentation defect too small to lead on its own, folded
  into the runtime paragraph above.
- `paper/` Section 5.1 (cited by the stale header block, U22-9) and
  `paper/figs/fig_yokoya_scans.pdf` (U22-13) are outside my region — flagged as seams.
- `validation/README.md`'s coherent-mode block (lines ~572-678) is outside my region;
  I checked only the two lines that bear on U22-10 (`:600` "rigid = 1", correct).
- Nothing in the EIC solve is left unverified: the repaired run
  (`probe_eic_corrected.jl`) and a **fully independent** asymmetric implementation
  (`probe_eic_independent.jl`) agree to five digits on both planes, so the cross kernels
  are validated in the asymmetric geometry as well as the symmetric one.
- The identity of the commit that moved the flat-beam strong-strong numbers (U22-17)
  was not bisected — 118 commits touched `src/` since the archive, each bisect step
  costs a ~2-minute run, and the cause is outside my region by construction.
