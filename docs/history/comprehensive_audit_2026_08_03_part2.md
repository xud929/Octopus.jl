# Comprehensive Audit — 2026-08-03, part 2

A second pass against the protocol in
[`docs/comprehensive_audit.md`](../comprehensive_audit.md), resuming from the
handoff in [part 1](comprehensive_audit_2026_08_03.md) §12 and following its
priority order. **Five confirmed defects, all fixed.**

The theme differs from part 1. That session found races — code that was wrong
whenever more than one thread ran. This one found **configuration that was
accepted, reported as active, and never used**: a solver whose CUDA launch
configuration was silently discarded while `configuration_report` claimed it
resolved, and a contract whose declared tolerances were overridden by its own
default. Nothing here changes a physics result. What it changes is whether the
repository's answer to "is this setting in effect?" can be trusted — which is
the question `AGENTS.md` cares most about, and the one part 1 did not ask.

## 1. Executive summary

| # | severity | area | state |
|---|---|---|---|
| S1 | **Moderate** | `GaussianPICPoissonSolver` silently discarded every CUDA PIC launch configuration *and* the policy thread count | fixed, verified |
| S2 | **Moderate** | a non-default CUDA-only Gaussian solver option was inactive on CPU with no signal on any surface | fixed, verified |
| S3 | Minor | `SymplecticityContract` and `validation/symplecticity_validation.jl` never enforced their four tightest declared tolerances | fixed, verified |
| S4 | Minor | the documented symplecticity of `:chromatic` and `:exact` virtual drifts was untested | fixed, verified |
| S5 | Minor (performance) | `beam_statistics` computed all 36 entries of a symmetric covariance | fixed, measured, bit-identical |

**The pattern worth taking away.** Part 1's lesson was "audit for checks that
exist and are never executed." This pass suggests the sibling rule: **audit for
values that are declared and never read.** S1, S2 and S3 are all the same
shape — a value stored, documented, and reported, with nothing downstream
consuming it. S1 is the sharpest case, because the introspection surface built
to answer exactly this question gave the wrong answer:
`configuration_report` reported `cuda_pic_kick_threads: requested=64,
resolved=64, status=resolved` while the runtime used 256.

`AGENTS.md` already states the rule — "Storing, documenting, or returning a
value from a configuration helper is not evidence that it is applied" — and
`ElementParameterEffectivenessContract` enforces it mechanically for *element*
parameters. No equivalent sweep exists for *solver* options, and S1 and S2 both
live in that gap.

## 2. Declared scope and coverage ledger

Scope was declared before reading anything in depth, following the part 1
handoff's priority order. `src/` is 31,005 lines.

### Read in full, line by line — 5,603 lines

| file | lines | handoff rank |
|---|---|---|
| `src/tasks/strongstrong/interface.jl` | 2,093 | 1 |
| `src/contracts/Contracts.jl` | 1,963 | 2 |
| `src/elements/strong_beam.jl` | 1,547 | 3 |

### Read in part — roughly 900 lines, in pursuit of specific questions

- `src/track/strong_beam_track.jl` l. 1–120 — the two `_run_logical_workers`
  luminosity accumulators, checked against the part 1 closure-capture class.
- `src/tasks/BeamObservers.jl` l. 700–1030 — observer output paths, the moment
  row builders, `_moment_live_flags`, `_scheduled_turns`.
- `src/knobs/Knobs.jl` — the epoch/lock handshake only (l. 112–166, 490–545).
- `src/beam/Beam.jl` — `beam_statistics`, `_live_stat_flags`,
  `_resolve_execution_policy`.
- `src/tasks/strongstrong/gaussian_pic.jl` l. 20–155; `pic_cpu.jl` l. 278–318;
  `pic_cuda.jl` l. 5030–5100; `policies/Policies.jl` l. 55–170.
- `docs/theory/beam_beam_longitudinal_kick.md` §7.1 in full.

### Whole-repository mechanical sweep

`Core.Box` census over lowered code: **3,112 functions/types, 2,110 Octopus
methods**. This covers every file including those never read by hand, for one
property only.

### Not inspected at all

`pic_cuda.jl` (5,807), `pic_cpu.jl` (1,715), `gaussian_pic_cuda.jl` (1,154),
`gaussian_pic.jl` bulk, `spectral.jl` (1,045), `spectral_cuda.jl` (760),
`Knowledge.jl` (885), `Tasks.jl` (753), `slicing.jl` (704), `Registry.jl` (209),
and `src/knobs/symbolic.jl` (285) — the one declared scope item **not reached**.
`test/runtests.jl` was run and edited, not read. `validation/` and `examples/`
were run, not read.

### Honest total

~6,500 of 31,005 lines (21%) read line by line this session. Part 1 reached
~7,800, on a disjoint file set — it explicitly listed `strong_beam.jl` as the
only unread element file, and never opened `interface.jl` or `Contracts.jl`.
Across the two sessions roughly **46% of `src/` has now been read line by
line**, with the beam-beam solver stack (`pic_cuda`, `pic_cpu`, `spectral`,
`gaussian_pic*`, ~11,300 lines) still the dominant gap.

### Equations independently derived

1. **Chromatic virtual drift**, against theory note §7.1, with `q = px²+py²`
   and `P = 1+pz`: `Φ = √(1 − q/2P²) − 1`, `Ψ = √(1 + q/2P²) − 1`, and all six
   components of both the forward and inverse maps. Exact match, including the
   factor of one half inside the radical, which comes from `dP²/dτ = −q/2` and
   is the one term that looks wrong until the derivation is read.
2. **Hirata paraxial drift**: `dP/dτ = −(∂S/∂z)H = −q/4` gives
   `pz −= 0.25(px²+py²)`, and `∂H/∂pz = 0` gives `z` unchanged — which is what
   the docstring's "no `pz` dependence, hence no path lengthening" means. It
   does *not* mean `pz` is unchanged, and the code is right.
3. **Exact-Hamiltonian drift**: the implicit solve `z₂ = (z + rr·z*)/(1 + rr)`
   with `rr = H/2p_s` verified to reproduce `S = (z_out − z*)/2`
   self-consistently — `z − 2rr·S = z₂` algebraically.
4. **Bassetti–Erskine kick**, verified against brute-force numerical
   integration (§6).
5. **`_equal_width_slices`** weights sum to exactly 1 for both odd and even
   `ns` — the telescoping `erf` sum reduces to `erf(nw·ns/2)/sumw`.
6. **`_equal_area_slices`** even-`ns` nodes are the equal-charge bin medians,
   `√2·erfinv((2i−1)/ns)`.
7. **`beam_statistics` covariance symmetry** is bit-exact, not approximate:
   `_covariance` sums `(a[k]−ma)(b[k]−mb)` in particle order and IEEE
   multiplication commutes (§8, verified by measurement).

## 3. S1 — a solver that composed instead of subtyping, and lost its configuration

`_with_solver_execution_configuration` (`interface.jl:199` before the fix)
installed the resolved CUDA PIC launch configuration only when
`solver isa PICPoissonSolver`. `GaussianPICPoissonSolver` **composes** a
`PICPoissonSolver` in its `pic` field (`gaussian_pic.jl:80`) rather than
subtyping it, so the scoped value was never installed and `_cuda_pic_threads`
(`interface.jl:216`) returned its hardcoded fallback:

```julia
config isa ResolvedCUDAPICLaunchConfig || return 256
```

`gaussian_pic_cuda.jl` calls that function at four sites (l. 690, 1002, 1013,
1026), and its routes reach further `pic_cuda.jl` kernels that call it too.

### What was claimed

- `gaussian_pic.jl:38-41`: "all PIC keywords (`grid`, ..., the CUDA execution
  options, ...) are forwarded to it unchanged".
- `CUDAPICLaunchConfig` docstring, `interface.jl:83`: "`nothing` inherits the
  thread count from `CUDAExecutionPolicy`".
- `configuration_report` reported the override as resolved.

All three were false for this solver.

### Evidence

Controlled pair, identical `CUDAPICLaunchConfig(kick_threads=64,
deposition_threads=64, field_threads=64)` under
`CUDAExecutionPolicy(threads=128)`:

| solver | before | after |
|---|---|---|
| `PICPoissonSolver` | (64, 64, 64) | (64, 64, 64) |
| `GaussianPICPoissonSolver` | **(256, 256, 256)** | (64, 64, 64) |
| `PICPoissonSolver`, no config | 128 — the policy | 128 |
| `GaussianPICPoissonSolver`, no config | **256** | 128 — the policy |

End to end, one turn, 512 particles per beam, counting `:cuda_pic_launch`
execution receipts:

| solver | before | after |
|---|---|---|
| PIC | 51 receipts, 7 families, threads {64, 128} | 51, unchanged |
| GaussianPIC | **0 receipts** | **56 receipts, 7 families, threads {64, 128}** |

The post-fix family list includes `:luminosity`, which is the part that matters
beyond tuning: `_resolve_cuda_pic_configuration` validates that the luminosity
thread count is a power of two (the overlap kernel uses a tree reduction that
orphans elements otherwise, per part 1 §9a) and that no family exceeds the
device maximum. Neither validation had ever run for this solver.

And `configuration_report(gpic; backend=CUDABackend)` reported
`cuda_pic_kick_threads: requested=64 resolved=64 status=resolved` — the
introspection surface asserting a value the runtime did not use.

**No physics impact.** Thread count is launch geometry; the CPU/CUDA
consistency contracts pass identically before and after. The impact is a public
performance-tuning surface that did nothing, an introspection surface that
misreported, and two safety validations that never executed.

**Fixed** by replacing the `isa` test with dispatch — `_pic_launch_solver`, with
a generic `nothing` fallback and a `PICPoissonSolver` method in `interface.jl`,
and the composing method beside the composing type at `gaussian_pic.jl:150`.
The same helper now drives the preflight, so composition is handled in one place
rather than at each `isa` site.

## 4. S2 — inactive on CPU, and silent on every surface

Two surfaces failed the same way for non-PIC solvers.

1. `configuration_report(::GaussianPoissonSolver)` (`interface.jl:1378` before
   the fix) accepted `policy` and `backend` keywords and used neither. So
   `batch_mode` — declared `supported_backends=(CUDABackend,)`, consumed at
   `pic_cuda.jl:5041` to choose the wavefront or sequential CUDA route, and
   genuinely inert on the CPU path — was reported `:resolved` on CPU. The PIC
   report already handled this correctly, so the two disagreed about the same
   option role.
2. `_preflight_solver_configurations!` (`interface.jl:1763` before the fix)
   opened with `solver isa PICPoissonSolver || continue`, so no non-PIC solver
   was ever checked for inactive CUDA-only options.

Net effect: `GaussianPoissonSolver(batch_mode=:sequential)` on CPU storage was
ignored, reported as active, and warned about nowhere.

### Evidence

`batch_mode=:sequential`, CPU backend:

| solver | report status before | after |
|---|---|---|
| PIC | `inactive_backend` | `inactive_backend` |
| Gaussian | **`resolved`** | `inactive_backend` |

Preflight warning, all three runs completing normally:

| case | before | after |
|---|---|---|
| PIC + `CUDAPICLaunchConfig` | WARNS | WARNS |
| GaussianPIC + `CUDAPICLaunchConfig` | **SILENT** | WARNS |
| Gaussian `batch_mode=:sequential` | **SILENT** | WARNS |

`SpectralPoissonSolver` declares no CUDA-only options, so generalizing the
preflight cannot produce a spurious warning there — checked before making the
change rather than after.

## 5. S3 — declared tolerances that never bound, in two files

`Contracts.jl:1193` and `validation/symplecticity_validation.jl:153` both
compute

```julia
tolerance = max(case.tolerance, default_tolerance)
```

which is a coherent design — `default_tolerance` is a floor, so raising it
relaxes every case at once. But both files shipped `default_tolerance = 5.0e-7`
while four cases declare `5.0e-8`, so `max` took the looser value and those four
declarations were decorative. Measured residuals for them are ~1.3–1.8e-13, so
nothing was failing; the point is that the number in the source was not the
number being enforced.

**Fixed** by lowering the floor in both files to `5.0e-8`, the tightest declared
value. Every per-case tolerance now binds exactly and `default_tolerance` keeps
its meaning. This is the same defect in two files, which is the shape part 1
found twice (F2/F3) and flagged as worth sweeping for.

| case | declared | enforced before | enforced after | residual |
|---|---|---|---|---|
| Linear6D | 5.0e-8 | 5.0e-7 | 5.0e-8 | 1.502e-13 |
| CrabDispersion | 5.0e-8 | 5.0e-7 | 5.0e-8 | 1.319e-13 |
| MomentumDispersion | 5.0e-8 | 5.0e-7 | 5.0e-8 | 1.807e-13 |
| XYCoupling | 5.0e-8 | 5.0e-7 | 5.0e-8 | 1.319e-13 |
| ThinCrabCavity | 5.0e-7 | 5.0e-7 | 5.0e-7 | 1.319e-13 |
| ChromaticityKick | 5.0e-6 | 5.0e-6 | 5.0e-6 | 4.163e-13 |
| ThinStrongBeam | 5.0e-7 | 5.0e-7 | 5.0e-7 | 7.908e-8 |
| GaussianStrongBeam | 5.0e-7 | 5.0e-7 | 5.0e-7 | 4.240e-8 |

## 6. S4 — two of three virtual drifts were symplectic by assertion only

`ThinStrongBeamSpec`'s docstring (`strong_beam.jl:135`) states: "All three are
exact flows of their own Hamiltonian, so all three are symplectic and telescope
exactly across slices." Both `SymplecticityContract` and
`validation/symplecticity_validation.jl` built their `ThinStrongBeam` case with
`virtual_drift=:hirata` and nothing else. `:chromatic` and `:exact` were covered
only by a CPU/CUDA parity test (`runtests.jl:5440`), which compares the map to
itself on another backend and cannot detect a non-symplectic map.

This is the configuration part 1 described for F2/F3 — "tests checked
`isfinite` and `isbits` but never symplecticity."

**Measured.** The step scan is what makes this a proof rather than a threshold:
a symplectic map's finite-difference residual is truncation error and falls as
`step²`, while a structurally non-symplectic map's residual is flat. The two
`UnsafeVirtualDrift` models are the negative control — documented as
non-symplectic, so a test that cannot separate them from the named three proves
nothing.

| drift | claimed | residual @ step 3e-7 | @ step 3e-6 | ratio | GaussianStrongBeam ns=5 |
|---|---|---|---|---|---|
| `:hirata` | symplectic | 7.908e-8 | 7.908e-6 | **100.0** | 4.240e-8 |
| `:chromatic` | symplectic | 7.908e-8 | 7.908e-6 | **100.0** | 4.240e-8 |
| `:exact` | symplectic | 7.908e-8 | 7.908e-6 | **100.0** | 4.240e-8 |
| `UnsafeVirtualDrift(:chromatic_frozen_energy)` | NOT | 2.047e-5 | 2.047e-5 | **1.0** | 1.476e-5 |
| `UnsafeVirtualDrift(:paraxial_frozen_longitudinal)` | NOT | 2.047e-5 | 2.047e-5 | **1.0** | 1.476e-5 |

Ratio 100 is exactly `(10)²`. The claim holds for all three, and the identical
residuals show the shared Gaussian kick sets the truncation floor — the drift
choice contributes nothing to it.

**Fixed** by adding `ThinStrongBeamChromatic` and `ThinStrongBeamExact` to
`_symplecticity_contract_cases()`, and a `runtests.jl` testset that asserts both
the `step²` scaling for the named three and the flat residual for the unsafe
two. The negative control is the part that gives the test discriminating power.

## 7. S5 — a symmetric matrix computed twice, measured rather than assumed

Part 1's handoff recorded, under "Open, not started": "The `beam_statistics`
covariance loop computes all 36 entries of a symmetric matrix (15 redundant
`O(N)` passes, per turn). Unmeasured, so a hypothesis." `Beam.jl:642` ran
`for i in 1:6, j in 1:6`.

**Measured**, minimum of seven runs, CPU:

| npart | `beam_statistics` before | after | `diagonal_fourth=true` before | after |
|---|---|---|---|---|
| 100 k | 2.288 ms | **1.385 ms** | 5.180 ms | **4.085 ms** |
| 1 M | 24.94 ms | **15.66 ms** | 55.36 ms | **42.87 ms** |

39.8% off the bare call and 22.6% off the `diagonal_fourth=true` form at 1 M
particles. The latter is the one that matters: `BeamMomentObserver.observe!` and
`JLD2BeamMomentObserver.observe!` call exactly that on every scheduled turn.

**The result is bit-identical, and that was verified rather than argued.**
`_covariance` sums `(a[k]−ma)(b[k]−mb)` over particles in index order; IEEE
multiplication commutes, so `cov[i,j]` and `cov[j,i]` were already equal to the
last bit. Checked directly: `cov[i,j] === cov[j,i]` bitwise `true` for all 36
entries at both particle counts, and the post-change library output compared
`===` against a locally computed 36-pass reference — identical at every entry.

## 8. Areas checked and found sound

- **The Bassetti–Erskine beam-beam kick, verified against an independent
  algorithm.** `gaussian_beambeam_kick` was compared to brute-force numerical
  integration of

      Kx = 2x ∫₀^∞ exp(−x²/(2σx²+t) − y²/(2σy²+t)) (2σx²+t)^{−3/2}(2σy²+t)^{−1/2} dt

  which shares no code with the Faddeeva closed form, the near-round `η` series,
  or the quintic blend between them. The reference self-checks against the exact
  round-beam form `2x(1−e^{−r²/2σ²})/r²` at 1.03e-14, which is its own accuracy
  floor. Sixteen field points per aspect ratio, `|x| ≤ 2.5σx`, `|y| ≤ 2.5σy`:

  | σx/σy | η | branch | max rel err Kx | max rel err Ky |
  |---|---|---|---|---|
  | 1.0 | 0 | round | 4.83e-14 | 4.83e-14 |
  | 1.0000001 | 1e-7 | series | 4.53e-14 | 4.04e-14 |
  | 1.0002 | 2.0e-4 | series | 4.32e-14 | 3.04e-14 |
  | 1.00024 | 2.4e-4 | **blend** | 2.32e-14 | 1.74e-14 |
  | 1.00025 | 2.5e-4 | **blend** | 2.69e-14 | 3.66e-14 |
  | 1.0003 | 3.0e-4 | **blend** | 4.63e-14 | 5.18e-14 |
  | 1.01 | 9.95e-3 | faddeeva | 6.58e-14 | 5.01e-14 |
  | 2.0 | 0.600 | faddeeva | 2.83e-14 | 3.57e-14 |
  | 11.0 | 0.984 | faddeeva | 4.62e-13 | 1.36e-13 |
  | 25.0 | 0.997 | faddeeva | 3.10e-10 | 4.77e-11 |

  All four branches agree at the reference's own floor. The blend window is
  narrow (`η ∈ [1.24e-4, 2.48e-4]` for `Float64`) and was targeted deliberately
  after the first sweep stepped over it — a sweep that misses the branch it was
  written to test is worth nothing. The growth at 25:1 is the reference
  integrand sharpening, not the evaluator.

- **The closure-capture class remains eliminated.** `Core.Box` census over
  lowered code, 2,110 Octopus methods, 8 boxes. Only one sits at a fan-out site:
  `_spectral_collide_longitudinal!` (`spectral.jl:983`), which part 1 already
  cleared as benign — the closure only reads `luminosity`, and the write happens
  after `@sync` has joined. The other seven have no `_run_logical_workers`,
  `Threads.@spawn`, `@async` or `@sync` anywhere in them.

  One entry is new relative to part 1's list of seven: `GaussianStrongBeam`'s
  constructor (`strong_beam.jl:349`), where `hoff_tuple`/`voff_tuple`/
  `pxoff_tuple`/`pyoff_tuple` are reassigned inside an `if` and captured by
  `ntuple` closures. It is host-side element construction with no fan-out, and
  the `ntuple` reads the old value before the assignment completes, so it is a
  type-instability smell rather than a race — the same standing as the spectral
  entry. It appears now because part 1's census scanned functions only; adding
  type constructors takes the method count from 1,792 to 2,110.

- **The knob epoch/recompile handshake.** Every mutation of `_KNOB_EPOCH`
  (`Knobs.jl:120`) happens under `_KNOB_LOCK`. `knob_epoch()` reads without the
  lock, which is a staleness window rather than a race — and the cache
  handshake in `_strong_strong_runtime_blocks` (`interface.jl:2003`) reads the
  epoch *before* building the runtime blocks and stores that value, so a knob
  changed during a build produces a mismatch and a rebuild at the next
  `execute!` rather than a lost update. The conservative ordering is the correct
  one and it is the one implemented.

- **`strong_beam_track.jl` worker accumulators.** Both
  `_track_thin_strong_beam!` and `_track_gaussian_strong_beam!` assign `value`
  only inside the `do` block, and `local_lum` inside a `for` body, which scopes.
  Neither is the part 1 F5/F6 shape. Confirmed by the census.

- **PTC contract coverage is complete today.** `_ptc_reference_specs()` declares
  55 cases; the committed `ptc_madx_5.03.06.tsv` contains exactly 55; the set
  difference is empty in both directions. No spec goes untested and no table row
  is silently dropped.

- **`_equal_width_slices` and `_equal_area_slices`** normalize and place nodes
  correctly for both odd and even `ns` (derivations in §2).

## 9. Corrections to this audit's own analysis

Recorded beside the conclusions, as the Absolute Rules require.

1. **The fingerprint diff first looked like my own fix had moved the CUDA PIC
   path.** Comparing before and after S1/S2/S3 showed 147 of 1,520 rows
   differing, all in `cuda/{pic,pic_cache,gpic,gpic_cache,spectral}`. That reads
   as a regression. Re-running the *unchanged* post-fix code produced 154
   differing rows in exactly the same five cases at the same magnitudes: the
   CUDA grid solvers are not bitwise reproducible run to run, and the
   before/after difference was entirely inside that noise. Everything
   deterministic — all seven CPU solver cases, both CUDA soft-Gaussian cases,
   all eight element configurations — was byte-identical throughout. A one-shot
   fingerprint comparison against a nondeterministic path proves nothing, which
   is the same lesson part 1 recorded as its correction #2. I repeated it.

2. **I nearly reported the "CPU/CUDA bit-parity" claims as a documentation
   defect.** Having measured that *no* solver is bitwise CPU/CUDA-identical
   (every one differs; max_abs 1.0e-16 to 2.7e-16), I was ready to call the four
   `src/` claims false. Checking the repository's own usage first showed
   "bit-parity" is a house term here, always quoted with its residual —
   `strong_strong_gaussian_pic_optimization_history.md:43` "bit-parity
   (~1e-15)", `:120` "1.2e-15 (lum) / 1.2e-12 (coords)", `todo.md:735` "lum
   ~2e-16, coords ~5e-13". My measured coordinate agreement, max_rel 2.4e-13 to
   2.7e-12, *reproduces* those recorded figures. Protocol principle 13: the
   repository's established convention wins. Not a finding, and the docstrings
   were left alone.

3. **The `0.5` in the chromatic drift looked like a factor-of-two error.**
   `phi = sqrt(1 - 0.5*(px*px + py*py)/((1+pz)*(1+pz))) - 1` does not match
   `p_s/(1+p_z)`, and my first reading was that it should have been the exact
   square root. Reading theory note §7.1 rather than guessing showed it is
   `Φ = √(1 − q/2P²) − 1` exactly, the one half coming from `dP²/dτ = −q/2`. The
   code is right and the derivation is where that is visible.

## 10. Test, contract and validation report

RTX 4500 Ada (24 GB, driver 580.119.02), 128 CPUs, Julia 1.12.4.

- `Pkg.test(julia_args=["--threads=8"])` **baseline, before any change:
  passed**, exit 0, 101 testsets.
- `Pkg.test(julia_args=["--threads=8"])` **after all fixes: passed**, exit 0,
  **102 testsets**, no failures and no errors. The new testset, "Virtual drifts:
  the named three are symplectic, the unsafe two are not", contributes 10
  assertions.
- Behavioural fingerprint, 7 solvers × 2 backends × 2 turns plus 8 element
  configurations, 1,520 full-precision rows: every deterministic case
  byte-identical to the pre-audit baseline. The five CUDA grid cases differ
  inside their measured run-to-run band (§9.1).

### Contracts — all 11 run, all passed

| contract | result | residual |
|---|---|---|
| `PTCConsistencyContract` | **PASS** | 4.995e-13 over 55 cases |
| `SymplecticityContract` (now 10 cases) | **PASS** | worst ratio 0.158 |
| `ElementParameterEffectivenessContract` | **PASS** | 238 parameters checked |
| `KnobEffectivenessContract` | **PASS** | 0.0 |
| `PublicConfigurationEffectivenessContract` | **PASS** | 0.0 |
| `HighEnergyWeakStrongLimitContract` | **PASS** | 3.010e-3 |
| `ElementTrackingBackendConsistencyContract`, audit line, CPU/CUDA | **PASS** | 8.327e-17 |
| `ElementTrackingBackendConsistencyContract`, reference line, CPU/CUDA | **PASS** | 0.0 |
| `StrongStrongGaussianBackendConsistencyContract` | **PASS** | 1.527e-17 |
| `StrongStrongPICBackendConsistencyContract` CIC/wavefront | **PASS** | 5.490e-17 |
| `StrongStrongPICBackendConsistencyContract` TSC/sequential | **PASS** | 5.952e-17 |

`PTCConsistencyContract` at 4.995e-13 is identical to part 1's figure, which is
the evidence that nothing in the magnet layer moved.

### Validation scripts

`AGENTS.md` requires `validate_configuration_metadata()` and
`validate(PublicConfigurationEffectivenessContract())` after changing solver
options or backend-specific launch configuration; both pass (the former runs
inside the latter).

- `validation/symplecticity_validation.jl` — **passed** for every element with
  the corrected tolerance floor; the four linear-map cases now judged at their
  declared 5.0e-8 rather than 5.0e-7 (§5).
- `validation/tracking_backend_consistency.jl` — **passed**,
  `max_abs_error = 2.0688e-17`, `global_rel_error` within tolerance, 10,000
  particles, 2 turns. Matches part 1's 2.07e-17.

**Not run this session**: the remaining 40 scripts in `validation/`. Part 1 ran
all 42 and repaired the one failure; nothing this session touches the element
layer or the solver kernels those scripts exercise, and the two scripts most
directly related to the changed surfaces were run.

## 11. Performance report

- **S5 is the only intentional performance change**: `beam_statistics` 24.94 →
  15.66 ms at 1 M particles, 55.36 → 42.87 ms with `diagonal_fourth=true`,
  bit-identical output (§7).
- **S1 restores a tuning surface rather than changing a default.** With the
  default `CUDAExecutionPolicy()`, `launch.threads` is 256 — exactly the
  hardcoded fallback that was being used — so default GaussianPIC runs are
  unchanged, which the fingerprint confirms. Only an explicitly non-default
  thread count now has an effect, which is the point.
- **S2, S3, S4 touch no hot path**: two are report/warning paths that run once
  per `execute!`, one is a tolerance constant, one adds test cases.

## 12. Change log

| file | change | finding |
|---|---|---|
| `src/tasks/strongstrong/interface.jl` | `_pic_launch_solver` dispatch helper replacing the `isa` test in `_with_solver_execution_configuration` | S1 |
| `src/tasks/strongstrong/gaussian_pic.jl` | `_pic_launch_solver(::GaussianPICPoissonSolver) = solver.pic` | S1 |
| `src/tasks/strongstrong/interface.jl` | `_preflight_solver_configurations!` covers every solver, not only PIC | S1, S2 |
| `src/tasks/strongstrong/interface.jl` | `configuration_report(::GaussianPoissonSolver)` honours `policy`/`backend` | S2 |
| `src/contracts/Contracts.jl` | `SymplecticityContract` tolerance floor 5.0e-7 → 5.0e-8 | S3 |
| `validation/symplecticity_validation.jl` | `DEFAULT_TOL` 5e-7 → 5e-8 | S3 |
| `src/contracts/Contracts.jl` | `thin_with(drift)` builder; `:chromatic` and `:exact` symplecticity cases | S4 |
| `test/runtests.jl` | virtual-drift symplecticity testset with step scan and unsafe-drift negative control | S4 |
| `src/beam/Beam.jl` | `beam_statistics` covariance upper triangle, mirrored | S5 |

## 13. Remaining risks

1. **~11,300 lines of the beam-beam solver stack remain unread** — `pic_cuda.jl`
   (5,807), `pic_cpu.jl` (1,715), `gaussian_pic_cuda.jl` (1,154),
   `spectral.jl` (1,045), `spectral_cuda.jl` (760), `gaussian_pic.jl` bulk. The
   consistency contracts exercise them end to end and pass at ~5e-17, which is
   real evidence, but it is behavioural agreement on one configuration each
   rather than a reading. This was part 1's largest risk and it still is.
2. **`src/knobs/symbolic.jl` (285) was declared in scope and not reached.**
3. **There is no `SolverOptionEffectivenessContract`.**
   `ElementParameterEffectivenessContract` sweeps all 238 element parameters
   mechanically and is what would have caught S1 and S2 had it covered solver
   options. `PublicConfigurationEffectivenessContract` checks the CUDA PIC
   launch families for `PICPoissonSolver` only — which is exactly why S1
   survived. **This is the highest-value next item**: the defect class is now
   demonstrated, and the enforcement pattern already exists one layer down.
4. **The CUDA grid solvers are not run-to-run bitwise reproducible** — measured
   at up to 1.3e-12 relative over two turns for `cuda/pic`, from float atomic
   deposition. The contracts' 1e-10 tolerance absorbs it and the soft-Gaussian
   CUDA path (no grid deposition) *is* bitwise reproducible, which is the
   control identifying deposition as the cause. This is inherent rather than a
   defect, but it is not stated anywhere in the docs, and a reproducibility-
   sensitive user would want to know.
5. **`PTCConsistencyContract` can silently narrow.** `haskey(specs, name) ||
   continue` (`Contracts.jl:1752`) skips any spec absent from the committed
   table, and nothing asserts that the 55 specs and 55 rows correspond. Coverage
   is complete today; a spec added without regenerating the table would reduce
   it with the contract still reporting PASS. A one-line count assertion closes
   it.
6. **`GaussianStrongBeamSpec`'s `:equal_area` docstring formula**,
   `z_k/sigz = sqrt(2)*erfinv(2k/ns)`, is the odd-`ns` form; the even-`ns` branch
   correctly uses `(2i−1)/ns`. The code is right, the formula as written covers
   half the cases.
7. **Part 1's risks 1a, 2, 5 and 6 are unchanged** — the F2/F3 configurations
   still have no external reference, GPU concurrency testing is still absent,
   `_SOL_CURVED_ORDER` is still not a public knob, and the BPM
   noise-repeats-within-a-turn question is still unverified.

## 14. Handoff — where the next session starts

### Done, do not redo

| area | state |
|---|---|
| `src/tasks/strongstrong/interface.jl` | **read in full** |
| `src/contracts/Contracts.jl` | **read in full** |
| `src/elements/strong_beam.jl` | **read in full**; beam-beam kick independently verified against numerical integration |
| Virtual drifts | all five measured for symplecticity, three now permanently tested |
| `Core.Box` class | swept again over 2,110 methods (up from 1,792); still eliminated |
| Contracts | all 11 run and passing |
| `beam_statistics` | measured and optimized, bit-identical |

### Next, in priority order

1. **A solver-option effectiveness contract** (risk 3). The pattern to copy is
   `ElementParameterEffectivenessContract`: build each solver through its
   constructor, perturb one declared option at a time, and assert the change is
   observable at its declared `consumer` — via execution receipts for execution
   options, coordinates for numerical ones. S1 and S2 are the proof it is
   needed.
2. `src/tasks/strongstrong/pic_cpu.jl` (1,715) — the CPU reference the CUDA
   paths are validated against; if it is wrong, every parity contract agrees on
   the wrong answer.
3. `src/tasks/BeamObservers.jl` (1,446) — only l. 700–1030 read.
4. `src/knobs/Knobs.jl` (896) + `symbolic.jl` (285) — only the epoch handshake read.
5. `src/tasks/strongstrong/pic_cuda.jl` (5,807) — the wavefront scheduler and
   Green cache; kernels are lower risk per part 1 §9a.

### Techniques that found things this session

- **Read the derivation before calling a constant wrong.** The chromatic drift's
  `0.5` looked like a factor-of-two error and is exactly right; §7.1 of the
  theory note says so in one line.
- **An independent algorithm beats a tighter tolerance.** Numerical integration
  of the Bassetti–Erskine integral tested the Faddeeva form, the `η` series and
  the blend simultaneously, and cost about thirty lines.
- **Target the branch, not the range.** The first Bassetti–Erskine sweep stepped
  straight over the blend window, which is 1.2e-4 wide. A sweep that misses the
  branch it was written to test is worth nothing.
- **A negative control is what makes a passing test mean something.** The two
  `UnsafeVirtualDrift` models are documented non-symplectic maps; without them,
  "the residual is below tolerance" says nothing about whether the test could
  detect a defect.
- **Grep for the consumer, not the declaration.** Every finding here was found
  by asking "what reads this?" and following it to a runtime site — which is how
  `_cuda_pic_threads`'s hardcoded `return 256` surfaced.
