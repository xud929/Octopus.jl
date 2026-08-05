# U25 Report — validation/ backend-consistency, PIC-option and benchmark scripts

Reading unit U25 of the 2026-08-05_b comprehensive audit.

---

## 1. Provenance and environment

- Repository `/cfs/ad/dxu/Library/Julia/Octopus`. **HEAD moved under this unit**:
  the brief named `7de4d81`; the tree was at `c55d2e0` when the unit started,
  and at `a120873` when it ended. The commits that landed mid-unit are
  `4ecc030` (*fix: destructive .lum prepare, unconverged curved solenoid*) plus
  docs/report commits. Before `4ecc030` was committed (19:15:55) its
  `interface.jl` half was already present as an uncommitted working-tree edit,
  so every strong-strong run below exercised the same code either way. The one
  run that straddled the **solenoid** half was
  `tracking_backend_consistency.jl` (19:10, pre-fix) — it was **re-run at
  `a120873` (post-fix) and produced identical numbers**, recorded below.
- Julia 1.12.4; NVIDIA RTX 4500 Ada (24.5 GB), CUDA runtime 13.0 / driver 13.3.
  **The box was shared with ~19 other audit agents** (16–19 concurrent `julia`
  processes observed). Every wall-clock number here is contaminated and is
  reported only as evidence that a run completed.
- **No repository file was modified.** All probes, scripts and output live under
  `scratchpad/audit/`. Two housekeeping notes, recorded because a reader should
  not have to wonder:
  - an early malformed shell command created three self-referential symlinks
    (`src/src`, `test/test`, `examples/examples`) inside the repository; they
    were removed within one tool call and `git status` was verified clean;
  - one benchmark run created (and this unit then removed) the empty directory
    `test/result/`, which is gitignored. See §6, U25-16.
- **Output redirection.** Most scripts in this region write under `<repo>/result/`.
  To keep the repository untouched *and* to avoid colliding with the other
  agents, each script was executed from a byte-identical **copy** in a scratch
  run-root, `scratchpad/audit/runroot/validation/`, whose siblings `src/`,
  `examples/` are symlinks back to the repository, whose `test/examples/` is a
  copy, and whose `result/` and `test/result/` are real scratch directories.
  Every script resolves its output directory from `@__DIR__`, so this redirects
  all output into scratch while running the real source tree
  (`--project=<repo>`), with the working directory set to the repository so the
  benchmark scripts' `git rev-parse HEAD` resolves.

## 2. Coverage

**Read line by line, every line:** `pic_option_consistency.jl` (233),
`tracking_backend_consistency.jl` (214), `pic_option_consistency_summary.jl` (151),
`pic_slice_boundary_jitter.jl` (129), `strong_strong_diagnostics_benchmark.jl` (123),
`counter_rng_validation.jl` (121), `tracking_context_policy_consistency.jl` (120),
`soft_gaussian_pic_comparison.jl` (117), `strong_strong_pic_extreme_benchmark.jl` (107),
`crossing_luminosity_anchor.jl` (99), `beam_optics_interface_consistency.jl` (79),
`strong_strong_pic_cache_backend_consistency.jl` (63),
`strong_strong_observer_plan_consistency.jl` (62), `tracking_task_turn_update.jl` (55),
`strong_strong_gaussian_backend_consistency.jl` (51),
`strong_strong_luminosity_schedule_output.jl` (47),
`strong_strong_diagnostics_consistency.jl` (45),
`moment_observer_backend_consistency.jl` (42),
`public_configuration_effectiveness.jl` (28), `tune_estimator_calibration.jl` (27),
`README.md` (890). Plus `git diff 6a3f39ab HEAD -- validation/` for the five
region files it touched.

**Read for cross-checking (not audited):** `src/contracts/Contracts.jl`
(the four contracts these scripts drive, `_contract_coordinate_metrics`,
`_contract_default_initial_rep`), `src/math/counter_rng.jl`,
`src/elements/aperture.jl`, `src/tasks/strongstrong/interface.jl`
(`LongitudinalSlicing` methods, `_CUDA_PIC_LAUNCH_FAMILIES`, solver options),
`src/tasks/strongstrong/pic_cuda.jl` (`:node`/wavefront route),
`src/tasks/BeamObservers.jl` (moment-file init/flush), `src/tasks/Tasks.jl`
(observer finalize), `test/examples/strong_strong_tracking.jl`,
`test/runtests.jl:3873` (Philox KAT testset), `AGENTS.md`,
`docs/comprehensive_audit.md` (Measured Lessons),
`docs/history/comprehensive_audit_2026_08_05_unit_reports/U21_report.md`.

**Executed:** all 20 region scripts were run (12 with a GPU leg forced on),
1 tripwire demonstration, 6 dedicated probes. Nothing in this region was left
unrun. Probes:
`probe_declaring_kinds.jl`, `probe_aperture_coverage.jl`,
`probe_rng_gate_insensitivity.jl` / `probe_rng_variants.jl`,
`probe_rng_threshold_scaling.jl`, `probe_moment_observer_file.jl`,
`tripwire/tracking_backend_consistency_missing_marker.jl`.

---

## 3. Hypothesis (a) — the GPU leg that never ran: per-script execution table

Every script in the region with a GPU path was run **with the GPU leg forced
on**. Gate names were read out of the code, not guessed. Result: **no script in
this region has a GPU leg that fails, errors, or silently reports success
without running.** This is the headline result of the unit.

| script | GPU gate (real name) | forced how | ran? | verdict | evidence |
|---|---|---|---|---|---|
| `tracking_backend_consistency.jl` | `OCTOPUS_RUN_GPU_CONTRACT` (`auto`/bool) + `OCTOPUS_REQUIRE_GPU_CONTRACT` | both `=1` | yes | **PASS** | CPU/GPU `status=passed`, `max_abs_error=1.665e-16`, `global_rel_error=7.73e-15`, 29 element kinds, 10 000 particles, 2 turns. Re-run post-`4ecc030`: identical. |
| `strong_strong_pic_cache_backend_consistency.jl` | `OCTOPUS_REQUIRE_GPU_CONTRACT` | `=1` | yes | **PASS** | `status=passed`, `max_abs_error=9.43e-17`, `luminosity_rel_error=6.57e-15`, `slice_pair_luminosity_records_compared=18` |
| `strong_strong_pic_cache_backend_consistency.jl` (TSC) | same + `OCTOPUS_CACHE_CONTRACT_DEPOSIT_METHOD=TSC` | `=1` | yes | **PASS** | `max_abs_error=7.45e-17`, `slice_pair_luminosity_rel_error=1.65e-14` |
| `strong_strong_gaussian_backend_consistency.jl` | `OCTOPUS_REQUIRE_GPU_CONTRACT` | `=1` | yes | **PASS** | `max_abs_error=1.52e-17`, `max_allowed_ratio=1.52e-7`, `luminosity_rel_error=5.53e-16` |
| `strong_strong_observer_plan_consistency.jl` | none — auto via `_contract_backends_available` | CUDA present | yes | **PASS** | `CUDABackend: max errors = 0.0, 0.0` |
| `beam_optics_interface_consistency.jl` | none — auto | CUDA present | yes | **PASS** | `CUDABackend: shared beam optics interface passed` |
| `tracking_context_policy_consistency.jl` | none — auto | CUDA present | yes | **PASS** | script's four CUDA assertions all silent; final line printed |
| `moment_observer_backend_consistency.jl` | hard `CUDA.functional() \|\| error` | CUDA present | yes | **PASS** | 28 columns, `max_abs=1.99e-17`, `max_rel=1.63e-13` vs `rtol=5e-12` |
| `public_configuration_effectiveness.jl` | contract returns `:skipped` w/o CUDA | CUDA present | yes | **PASS** | `cuda_status=passed`, `cuda_pic_families_observed` = all 7 families, sequential + wavefront branches both effective |
| `soft_gaussian_pic_comparison.jl` | hard `available \|\| error` | CUDA present | yes | **PASS (characterization)** | ran at 20 k/5 slices/64²: `luminosity_relative_difference = 5.26e-4` |
| `pic_option_consistency.jl` | `OCTOPUS_OPT_BACKEND=gpu` | `=gpu` | yes | **PASS** | GPU arm vs CPU base: per-particle `rms_dx/sigx = 4.2e-15`, `rms_dy/sigy = 5.4e-14` |
| `strong_strong_diagnostics_benchmark.jl` | `OCTOPUS_USE_GPU` (default `1`) | default | yes | **PASS** (`baseline`, and `both` on retry) | see §6 U25-16 for the first `both` run, which failed for an infrastructure reason, not a code reason |
| `strong_strong_pic_extreme_benchmark.jl` | `OCTOPUS_USE_GPU` (default `1`) | default, frozen settings | yes | **PASS** | 30 turns at 2.56M/1.0M, 128², 15 slices; `steady_last_ten_mean = 0.270 s` (**shared GPU — not a clean measurement**) |

CPU-only scripts in the region, all run, all exit 0:
`counter_rng_validation.jl` (philox and splitmix), `tracking_task_turn_update.jl`,
`strong_strong_diagnostics_consistency.jl`,
`strong_strong_luminosity_schedule_output.jl`, `tune_estimator_calibration.jl`,
`pic_slice_boundary_jitter.jl`, `crossing_luminosity_anchor.jl`,
`pic_option_consistency_summary.jl`.

**Silently-skipped audit.** Of the twelve GPU-capable scripts, none can report
success without saying so: three print `status = skipped` and honour
`OCTOPUS_REQUIRE_GPU_CONTRACT`; three print an explicit `... skipped: <reason>`
line; two hard-error; one is a contract that returns `:skipped`; three require a
GPU by configuration. The residual gap is that the "print a skip line" group has
**no way to require** the GPU leg — see U25-12.

---

## 4. Hypothesis (b) — the declaration↔coverage tripwire

### 4.1 The tripwire fires (demonstrated)

`validation/tracking_backend_consistency.jl:157-172` walks
`Octopus.registered_element_specs()`, collects every kind whose `ElementMeta`
declares `ElementTrackingBackendConsistencyContract`, and errors on
`setdiff(declaring, covered)`.

Measured, current state (`probe_declaring_kinds.jl`): **29 declaring kinds, 29
covered, 0 uncovered.** 30 spec types are registered; the only non-declaring
kind is the composite `:line`. `rbend` is not a separate kind (RBEND reaches the
`:sbend` map), which is why the line's 29 entries suffice.

Demonstration that removing a declaring kind fails the run: a scratch copy with
`MarkerSpec(),` commented out —

```
$ julia --project=<repo> scratch/.../tracking_backend_consistency_missing_marker.jl
ERROR: LoadError: kinds declare ElementTrackingBackendConsistencyContract but are
missing from this line: marker
  [2] top-level scope @ ...:169
EXIT=1
```

It fires **before** either contract is constructed, names the missing kind, and
exits non-zero. The tripwire works as advertised.

### 4.2 Every other case list in the region

| script | case list | authoritative source | tripwire? |
|---|---|---|---|
| `tracking_backend_consistency.jl` | 29 element specs in `line` | `registered_element_specs()` + `ElementMeta.contracts` | **YES** — demonstrated above |
| `strong_strong_pic_extreme_benchmark.jl:94` | 7 CUDA PIC launch families | `Octopus._CUDA_PIC_LAUNCH_FAMILIES` (interface.jl:72) | **PARTIAL** — `only(filter(...))` throws if a *listed* family disappears; a *newly added* family is silently omitted (U25-8) |
| `strong_strong_diagnostics_benchmark.jl:108` | same 7 families | same | **NO** — `isempty(matches) && continue` swallows both directions (U25-8) |
| `pic_slice_boundary_jitter.jl:108` | `(:equal_area, :normal_quantile)` | `LongitudinalSlicing` accepts 8 symbols / 5 distinct families (interface.jl:700) | **NO** — deliberate scope (the two production methods); low risk, noted not raised |
| `counter_rng_validation.jl:35-38` | `philox` / `splitmix` | `rng_method_code` (counter_rng.jl:66) | **NO** — errors on an unknown env value, but a third method added to the RNG would be silently untested |
| `strong_strong_diagnostics_benchmark.jl:23` | 5 benchmark modes | self-defined by the script | n/a — no external authority, no hand-copy risk |
| `public_configuration_effectiveness.jl` | none — delegates to the contract | — | n/a (best pattern in the region: the contract owns its own coverage and reported all 7 families in the GPU run) |
| `tracking_context_policy_consistency.jl` | receipt consumer names | `_record_execution!` call sites | n/a — a rename makes `any(...)` false, i.e. fails loudly |

---

## 5. Hypothesis (d) — every threshold, ENFORCED or PRINT-ONLY

| script | threshold | status |
|---|---|---|
| `tracking_backend_consistency.jl` | `atol=1e-10`, `rtol=1e-10` (CPU/CPU) | **ENFORCED** (`passed \|\| error`) |
| | same (CPU/GPU) | **ENFORCED** (`status==:failed → error`) |
| | GPU skipped while `OCTOPUS_REQUIRE_GPU_CONTRACT=1` | **ENFORCED** |
| `strong_strong_pic_cache_backend_consistency.jl` | `OCTOPUS_CACHE_CONTRACT_RTOL=1e-10` (coord + luminosity) | **ENFORCED** |
| | skip + `REQUIRE_GPU` | **ENFORCED** |
| `strong_strong_gaussian_backend_consistency.jl` | `OCTOPUS_GAUSSIAN_CONTRACT_RTOL=1e-10` | **ENFORCED** |
| `strong_strong_observer_plan_consistency.jl` | `atol=0`, `OCTOPUS_OBSERVER_PLAN_RTOL=1e-12` | **ENFORCED** |
| `moment_observer_backend_consistency.jl` | `rtol=5e-12`, `atol=1e-18`; CUDA presence | **ENFORCED** (both) |
| `beam_optics_interface_consistency.jl` | exact `==` (legacy vs 3-plane; vs sigma reference; unrelated coords) | **ENFORCED** |
| | `rtol=2eps` (sigma vs emittance), `rtol=atol=4eps` (alpha_z), exact `==` (ChromaticityKick) | **ENFORCED** |
| `tracking_context_policy_consistency.jl` | CPU fast/planned `max_abs_error == 0` | **ENFORCED** |
| | CUDA launch-geometry `max_abs_error == 0`; CPU/CUDA `1e-10/1e-10`; fused-receipt presence; legacy-path absence; `count(:isolated_tracking)==2`; 2 luminosity rows | **ENFORCED, but only when CUDA is visible** (no way to require — U25-12) |
| `tracking_task_turn_update.jl` | `max_abs_error == 0` | **ENFORCED** |
| `strong_strong_diagnostics_consistency.jl` | exact array equality; `length(turn_timings)==2`; summary identity; `isempty(pic_phase_timings)` | **ENFORCED** |
| `strong_strong_luminosity_schedule_output.jl` | exact 4-row match incl. evaluated `NaN` and header | **ENFORCED** |
| `public_configuration_effectiveness.jl` | `validate_configuration_metadata()`; contract `:failed` | **ENFORCED**; `:skipped` exits 0 **by design** (documented) |
| `counter_rng_validation.jl` | `\|mean\|<5e-3`, `\|var−1\|<1e-2`, `\|umean−0.5\|<5e-3`, `\|uvar−1/12\|<5e-3`, `\|corr_pair\|<5e-3`, `\|corr_neighbor\|<5e-3`, reproducibility, stream/turn separation | **ENFORCED** — but absolute, not N-scaled (U25-4), and blind to the generator itself (U25-3) |
| | `P(\|N\|>2/3/4)` vs "expected about 0.0455003 / 0.0026998 / 6.334e-5" | **PRINT-ONLY** |
| `strong_strong_pic_extreme_benchmark.jl` | `length(timings) >= 20` | **ENFORCED** (structural) |
| | `only(filter(...))` per launch family | **ENFORCED** (structural, one direction) |
| | all timing numbers | **PRINT-ONLY** (by design — it is a benchmark) |
| `strong_strong_diagnostics_benchmark.jl` | mode ∈ 5 names; `turns >= sample_turns` | **ENFORCED** (structural; the second checks the wrong quantity — U25-7) |
| | all timing/byte numbers | **PRINT-ONLY** (by design) |
| `pic_option_consistency.jl` | none | **PRINT-ONLY / characterization** (writes 4 files) |
| `pic_option_consistency_summary.jl` | none — `lum_reldiff`, `epsy/epsx_reldiff`, `lum_drift`, per-particle `rms/max` all printed | **PRINT-ONLY** |
| `pic_slice_boundary_jitter.jl` | none | **PRINT-ONLY** (README says so) |
| `soft_gaussian_pic_comparison.jl` | CUDA presence | **ENFORCED**; every physics number **PRINT-ONLY** (README says so) |
| `crossing_luminosity_anchor.jl` | none — `R_code/R_discrete` printed | **PRINT-ONLY** |
| `tune_estimator_calibration.jl` | none — median/p95/max printed | **PRINT-ONLY** |

Count: 13 scripts enforce at least one numerical threshold; 6 are pure
characterization; `counter_rng_validation.jl` enforces six statistics and prints
three more.

---

## 6. Leads

### LEAD U25-1 [medium, confidence high] validation/pic_option_consistency.jl:119-124 (+ :226-228)
Claim: on the GPU, choosing `interaction_grid=:node` or `slice_interpolation=:quadratic`
silently *also* switches `batch_mode` to `:sequential` and `cuda_async` to `false`,
and the run's `meta.tsv` records neither — so the per-turn cost the script
attributes to the option is confounded with a batching change that nothing in the
recorded provenance mentions.
Mechanism: the solver constructor computes
`batch_mode = isempty(cfg.batch_mode) ? ((backend===:gpu && (igrid===:node || sinterp===:quadratic)) ? :sequential : :wavefront) : …`
and the matching negation for `cuda_async`. The `meta.tsv` header (line 227)
writes `tag backend turns npart npart_e npart_p grid nslices interaction_grid
slice_interpolation deposit grid_extent grid_quantize mean_turn_s timing_from` —
no `batch_mode`, no `cuda_async`. The downgrade is not forced by the runtime:
`cuda_indexed_wavefront` defaults to `true` (interface.jl:1234) and the CUDA
wavefront route supports `:node` through the fully-indexed sub-route
(pic_cuda.jl:220-235 rejects only the *non*-indexed combination). The script's
own docstring says its purpose is that "the cost ordering of the options is grid-
and particle-count dependent", so a confounded cost is exactly the thing it
exists to report. `OCTOPUS_OPT_BATCH_MODE`/`OCTOPUS_OPT_CUDA_ASYNC` exist as
escape hatches but appear in neither the script header nor the README.
Repro: run two GPU arms and diff the meta rows —
```
OCTOPUS_OPT_TAG=gpu  OCTOPUS_OPT_BACKEND=gpu OCTOPUS_OPT_TURNS=6 OCTOPUS_OPT_NPART=2000 \
  OCTOPUS_OPT_TIMING_FROM=3 OCTOPUS_OPT_GRID=32 OCTOPUS_OPT_NSLICES=5 julia … pic_option_consistency.jl
OCTOPUS_OPT_TAG=node OCTOPUS_OPT_BACKEND=gpu OCTOPUS_OPT_INTERACTION_GRID=node … (same)
```
Measured here: `mean_turn_s` 0.0252 s (gpu) vs 0.0617 s (node) — a 2.4x "cost of
`:node`" that also contains sequential-vs-wavefront and async-off; and
`result/pic_option_node.meta.tsv` records only `interaction_grid node`.

### LEAD U25-2 [medium, confidence high] validation/counter_rng_validation.jl:86-92
Claim: the script's gate is a *statistics* test, not a *generator* test — it
accepts a Philox4x32 with the Weyl key bump removed — so the file that presents
itself as "the counter RNG validation" cannot detect the regression class it
looks like it covers; the real anchor is a testset in `test/runtests.jl` that
neither the script nor the README mentions.
Mechanism: `ok` is the conjunction of six moment/correlation bounds plus
reproducibility and stream separation. All of them are satisfied by any
generator with good low-order statistics, whatever its round function.
Repro (`probe_rng_gate_insensitivity.jl` / `probe_rng_variants.jl` — replicates
the script's eight criteria over a locally-built Philox with `NR` rounds and the
Weyl bump switchable; the reference variant reproduces the production
`corr_neighbor = 0.00023777781906113323` bit-for-bit, which validates the
replica):

| variant | corr_neighbor | script gate `ok` |
|---|---|---|
| 10 rounds + Weyl bump (= production) | 2.378e-4 | **true** |
| **10 rounds, Weyl key bump REMOVED** | 4.154e-4 | **true** ← regression accepted |
| **3 rounds, bump kept** | −3.364e-3 | **true** ← regression accepted |
| 3 rounds, no bump | 6.526e-2 | false |
| 2 rounds, bump | 0.99991 | false |

The official Random123 known-answer vectors *are* checked, but in
`test/runtests.jl:3873` ("Philox4x32-10 matches the Random123 known-answer
vectors", added for U15-1), not here. Region-scoped defect: the script header
("Validate the counter-based RNG…") and README §Counter RNG ("checks the
Philox-based stateless counter RNG…") neither state the limitation nor point at
the KAT gate. Cross-region note (seam, not pursued): that testset re-drives the
round loop with a locally written `philox10` that duplicates
`counter_philox4x32`'s key-bump schedule, so it pins `_philox4x32_round` and the
constants but not the driver; U14 of this audit covered the generator itself.

### LEAD U25-3 [medium, confidence high] validation/counter_rng_validation.jl:86-92
Claim: the same gate's tolerances are fixed absolute constants while the
statistics they bound scale as `1/sqrt(N)`, so at the smaller `N` the README
itself recommends a **healthy** generator fails the gate.
Mechanism: `|mean| < 5e-3` against a sampling error of `1/sqrt(N)` is 5σ at the
default `N=1e6`, 2.2σ at `N=2e5`, 1.6σ at `N=1e5`; the two correlation bounds
have the same shape and `|var−1| < 1e-2` is `sqrt(2/N)`-limited. README lines
193-197 advertise `OCTOPUS_RNG_VALIDATION_N=200000` as "a smaller check".
Repro (`probe_rng_threshold_scaling.jl`, 12 seeds per cell, real
`counter_normal`/`splitmix_normal`):

| backend | N=1e6 | N=2e5 | N=1e5 |
|---|---|---|---|
| philox | 0/12 fail | 0/12 | **3/12** |
| splitmix | 0/12 | **1/12** | **3/12** |

Single-command reproduction of a false failure:
```
OCTOPUS_RNG_VALIDATION_BACKEND=splitmix OCTOPUS_RNG_VALIDATION_N=200000 \
OCTOPUS_RNG_VALIDATION_SEED=2 julia --project=. validation/counter_rng_validation.jl
→ normal mean = 0.005525271894064565
→ ERROR: LoadError: counter RNG validation failed   (exit 1)
```

### LEAD U25-4 [medium, confidence high] validation/tracking_backend_consistency.jl:154 (seam: src/contracts/Contracts.jl `_contract_coordinate_metrics`)
Claim: `:aperture` is covered by the tripwire **by name only** — with the
committed limits no particle can ever reach it — and it *cannot* be covered
properly, because the contract's comparator rejects lost particles even when the
two backends agree exactly.
Mechanism: the line entry is `ApertureSpec(shape=:ellipse, x_limit=1.0,
y_limit=1.0)` while `_contract_default_initial_rep` builds `|x| ≤ 1e-4`,
`|y| ≤ 8e-5`; the element is therefore the identity map on both backends, and
the only behaviour an aperture has — killing a particle — is never executed.
Making it realistic does not work either: `_aperture_kill` writes `NaN` into all
six coordinates (aperture.jl:260), `_contract_coordinate_metrics` computes
`diff = abs(NaN − NaN) = NaN`, `max(x, NaN) = NaN` in Julia, and
`passed_tolerance = (NaN <= 1.0) = false`. The in-file comment ("the aperture
generous: … a lost … particle tests less of the map, not more") documents the
choice but not that the comparator forces it.
Repro (`probe_aperture_coverage.jl`):
```
committed aperture limits = (1.0, 1.0) m
max |x| in the contract rep = 9.999999998313447e-5
max |y| in the contract rep = 7.999999828658556e-5
particles that could ever reach the committed ellipse: 0

CPU/CPU with a REALISTIC aperture (5e-5 m):   [7487 of 10000 lost, identically, both runs]
  status = failed
  max_abs_error = NaN
  passed_tolerance = false
```
Same argument, weaker consequence, for `MarkerSpec()` — a documented no-op, so
"covered by name" is all there is to cover.

### LEAD U25-5 [minor, confidence high] validation/strong_strong_diagnostics_benchmark.jl:26-64
Claim: the script's turn count and the harness's turn count are two different
variables, and the guard checks the wrong one, so a pre-set `OCTOPUS_TURNS`
destroys the run with a `BoundsError` *after* the whole measured workload.
Mechanism: `turns` comes from `OCTOPUS_DIAGNOSTIC_BENCHMARK_TURNS`; the defaults
loop is `haskey(ENV, key) || (ENV[key] = value)`, so an externally set
`OCTOPUS_TURNS` wins and the harness runs a different number of turns. The guard
`turns >= sample_turns` compares the script's own two numbers, never
`length(timings)`, and then `sample = timings[(end - sample_turns + 1):end]`
indexes out of range. The sibling `strong_strong_pic_extreme_benchmark.jl:46`
guards correctly (`length(timings) >= 20 || error(...)`), which is the fix
shape. `OCTOPUS_TURNS` is a documented harness knob and the sibling benchmark's
header explicitly invites overriding "the same environment variables accepted by
`test/examples/strong_strong_tracking.jl`".
Repro (measured):
```
OCTOPUS_USE_GPU=0 OCTOPUS_TURNS=4 OCTOPUS_N_MACRO_ELE=5000 OCTOPUS_N_MACRO_PRO=5000 \
  julia --project=. validation/strong_strong_diagnostics_benchmark.jl
→ ERROR: LoadError: BoundsError: attempt to access 4-element Vector{Float64} at index [-95:4]
```

### LEAD U25-6 [minor, confidence high] validation/strong_strong_diagnostics_benchmark.jl:108 and validation/strong_strong_pic_extreme_benchmark.jl:94
Claim: both benchmark scripts hand-copy the CUDA PIC launch-family list instead
of deriving it, and neither has a tripwire for a *newly added* family — the
Measured-Lesson-4 shape that `tracking_backend_consistency.jl` just fixed for
element kinds.
Mechanism: the authoritative list is
`Octopus._CUDA_PIC_LAUNCH_FAMILIES = (:gather_scatter, :deposition, :kick,
:field, :spectral, :green, :luminosity)` (interface.jl:72). The extreme
benchmark's `only(filter(item -> item.name === option, config_entries))` throws
if a *listed* family vanishes, but an eighth family simply never appears in the
provenance summary. The diagnostics benchmark is weaker still:
`matches = filter(...); isempty(matches) && continue` swallows both directions,
so its summary can lose a family silently. Both lists are currently correct
(verified against the constant, and the GPU contract run reported exactly those
seven as `cuda_pic_families_observed`).
Repro: `grep -n "_CUDA_PIC_LAUNCH_FAMILIES" src/tasks/strongstrong/interface.jl`
and compare with the `for family in (…)` tuple in each benchmark; the fix is to
iterate the constant.

### LEAD U25-7 [minor, confidence high] validation/README.md §"Beam Optics Interface Consistency"
Claim: the README credits the script with a check it does not perform — "and
CPU/CUDA agreement". No CPU-versus-CUDA comparison exists anywhere in the file.
Mechanism: `check_backend(CPUThreadsBackend)` and `check_backend(CUDABackend)`
each compare *within* one backend (legacy vs three-plane alpha, sigma vs
emittance, alpha_z normalization). Arrays from the two backends are never
compared to each other. The script's own header is accurate ("The checks run on
CPU and CUDA when CUDA is available"); the README's summary is not.
Repro: `grep -n "check_backend\|CUDABackend" validation/beam_optics_interface_consistency.jl`
— lines 70-72 are the only cross-backend appearance, and they are two
independent calls.

### LEAD U25-8 [minor, confidence high] validation/README.md and three script headers — undocumented outputs
Claim: four output files that the region actually writes are named in neither
the README nor the owning script's header, violating AGENTS.md §"Updating
Validations" ("state the reference model, error metric, output files, and run
command").
Mechanism, file by file:
- `pic_option_consistency.jl:151` writes `result/pic_option_<tag>.lum`; its own
  "Outputs (under `result/`)" block lists only `.tsv`, `.coords.tsv`,
  `.meta.tsv`, and so does README line 776-778. (Verified present: scratch
  `result/pic_option_base.lum` etc.)
- `strong_strong_pic_extreme_benchmark.jl:12` says "Outputs are the printed
  physics summary and `result/pic_extreme_turn_times.tsv`" but line 58 also
  writes `result/pic_extreme_summary.tsv` — the file that carries the whole
  provenance record (git commit, GPU, driver, resolved launch config). The
  README does not name it either.
- `strong_strong_diagnostics_benchmark.jl` names **no** outputs in its header,
  and README §"Strong-Strong Diagnostic Output Benchmark" names none; it writes
  `result/pic_diagnostics_<mode>_turn_times.tsv` and
  `result/pic_diagnostics_<mode>_summary.tsv`, plus (via the harness, in
  `moments`/`both`/`luminosity_io` modes) `test/result/pic_hcc.lum`,
  `pic_hcc.ele.h5`, `pic_hcc.pro.h5`.
- `counter_rng_validation.jl` documents `OCTOPUS_RNG_VALIDATION_WRITE_CSV` in
  its header and the README shows the command, but neither says where the CSV
  lands — and the destination *changed* in this audit window (U19-8 moved it
  from `validation/` to `result/counter_rng_validation_summary.csv`).
Repro: run each script and `ls` its result directory against the documented list.

### LEAD U25-9 [minor, confidence med] validation/README.md §soft_gaussian_pic_comparison and §moment_observer_backend_consistency; validation/moment_observer_backend_consistency.jl:1-4
Claim: two scripts abort immediately without a GPU, and the README presents both
as ordinary `julia --project=. …` runs; one of them also has no run command,
metric or output statement in its own header.
Mechanism: `soft_gaussian_pic_comparison.jl:32-33` is
`available || error("CUDA is required for this comparison: $reason")` — the
header was updated for this in the audit window (U20-8) but README lines 357-366
were not. `moment_observer_backend_consistency.jl:13` is
`CUDA.functional() || error(...)`, and its four-line header states neither the
requirement, nor the run command, nor the tolerance, nor that it writes nothing.
README lines 450-455 likewise omit the requirement.
Repro: `CUDA_VISIBLE_DEVICES="" julia --project=. validation/moment_observer_backend_consistency.jl`
→ `ERROR: CUDA is required for moment observer backend consistency`, while the
README's line above it reads as an unconditional check.

### LEAD U25-10 [minor, confidence high] validation/tracking_context_policy_consistency.jl, strong_strong_observer_plan_consistency.jl, beam_optics_interface_consistency.jl
Claim: three scripts print their CUDA skip but offer no way to *require* the GPU
leg, unlike the three contract scripts beside them — so on a CPU-only machine
`tracking_context_policy_consistency.jl` exits 0 having run one of its four
documented checks, and CI cannot tell that apart from a full pass.
Mechanism: each does `available, reason = Octopus._contract_backends_available(CUDABackend)`
and then `if available … else println("… skipped: ", reason)`. There is no
`OCTOPUS_REQUIRE_GPU_CONTRACT` branch, though the environment variable already
exists and is honoured by
`tracking_backend_consistency.jl`, `strong_strong_pic_cache_backend_consistency.jl`
and `strong_strong_gaussian_backend_consistency.jl`. This is the "loud beats
silent" rule at half strength: the skip is visible, but not assertable. Note the
README (line 44-46) describes the CUDA-only half of
`tracking_context_policy_consistency.jl` ("CUDA launch geometry does not change
counter-RNG samples") as if it always runs.
Repro: `CUDA_VISIBLE_DEVICES="" julia --threads=4 --project=. validation/tracking_context_policy_consistency.jl`
→ prints `CUDA radiation checks skipped: …` and then
`tracking context/policy consistency validation passed`, exit 0.

### LEAD U25-11 [minor, confidence high] validation/pic_option_consistency_summary.jl:55-58, 90-102
Claim: the summary pairs a run with its baseline by tag suffix alone and never
checks that the two runs used the same particle count, although `meta.tsv`
carries `npart` and the code comment claims the property it does not verify.
Mechanism: the comment at line 55-57 says "Compare each run against the baseline
with the SAME particle count: a 2k-particle run and a 50k-particle run differ by
shot noise, which has nothing to do with the option under test", and the entire
mechanism is `baseline_for(tag) = endswith(tag, "_c") ? "base_c" : "base"`.
Nothing rejects, or even annotates, `runs[tag]["npart"] != runs[bt]["npart"]`, so
a mistyped tag silently converts shot noise into a reported option drift. The
sibling defect on the same line was just fixed loudly (U21-9 added the
`SKIPPED (no baseline run found)` line), which is the pattern to copy.
Repro: produce two arms with different `OCTOPUS_OPT_NPART` and the same suffix
class (e.g. `base` at 50 000 and `quad` at 2 000), then run
`julia --project=. validation/pic_option_consistency_summary.jl`: the table
prints an `lum_reldiff_mean` for `quad` with no warning, and the `npart` column
is the only clue.

### LEAD U25-12 [minor, confidence high] validation/README.md:881-890 and validation/{crossing_luminosity_anchor,tune_estimator_calibration}.jl
Claim: the two entries added for U21-1 are attached to the wrong section and
still do not state the error metric or the outputs; and neither script carries a
run command in its own header.
Mechanism: the bullets sit at the very end of "## PTC Reference and Lattice
Cells", a section about MAD-X/PTC and lattice composition, with no heading of
their own. `crossing_luminosity_anchor.jl` writes `result/lum_anchor/lum_headon.lum`,
`lum_crossing.lum`, `lum_crab.lum` (documented nowhere) and its five-line header
gives the reference model but no run command and no outputs.
`tune_estimator_calibration.jl` has a two-line header: no run command, no metric
statement (it reports median/p95/max of `|Q̂ − Q1|` over 500 trials), no note
that it writes nothing.
Repro: `sed -n '811,890p' validation/README.md` — the bullets follow
`lattice_cells.jl`'s "Outputs `result/lattice_cells.tsv`" paragraph with no
intervening heading; `ls result/lum_anchor/` after a run shows three undocumented
files.

### LEAD U25-13 [minor, confidence high] validation/README.md:213-256 §"Tracking Backend Consistency"
Claim: the README entry for the region's most important script was not updated
when the script tripled its coverage, so the index understates what the check is
and omits the tripwire that now defines its contract with future authors.
Mechanism: the entry still reads "runs `ElementTrackingBackendConsistencyContract`
on a deterministic mixed tracking line, including stochastic `LumpedRad`". Since
U21-5 the line carries **all 29 kinds** that declare the contract — the whole
thick-magnet family, every thin element, patch, marker, aperture, RF cavity —
and a declaration↔coverage tripwire that fails the run when a new declaring kind
is not added. A future author reading only the README will not know either fact.
The env list (lines 250-256) also omits `OCTOPUS_CONTRACT_SEED`, which the script
header documents.
Repro: `grep -c "Spec(" validation/tracking_backend_consistency.jl` (29 entries
in `line`) against the README's one-sentence description; `grep -n
"OCTOPUS_CONTRACT_SEED" validation/README.md` → 0.

### LEAD U25-14 [info, confidence high] validation/crossing_luminosity_anchor.jl:6
Claim: the only script in the region whose `include` of `src/Octopus.jl` is not
guarded by `if !isdefined(Main, :Octopus)`. Harmless standalone (it is how the
script is run), but it cannot be included after any sibling in one process, and
it breaks the region's otherwise uniform convention.
Repro: `head -8 validation/crossing_luminosity_anchor.jl` vs the same lines of
any other script in the region.

### LEAD U25-15 [info, confidence med] validation/strong_strong_{diagnostics,pic_extreme}_benchmark.jl — undeclared dependency on harness globals
Claim: both benchmark scripts read a dozen globals that leak out of
`test/examples/strong_strong_tracking.jl` (`task`, `timings` via
`turn_timings(task)`, `luminosity_path`, `electron_moment_path`,
`proton_moment_path`, `stats_ele`, `stats_pro`, `solver`, `policy`, `input`,
`CUDA`), none of which is a documented interface. A rename in the harness breaks
both validation scripts with an `UndefVarError` at the end of a production-size
GPU run.
Repro: `grep -n "stats_ele\|electron_moment_path\|input\.solver" validation/strong_strong_*benchmark.jl`
and note that none of those names appears in the harness's own documented
`OCTOPUS_*` interface.

### LEAD U25-16 [info — infrastructure, confidence high] seam: test/examples/strong_strong_tracking.jl fixed output directory
Claim (out of hypothesis, and partly an artefact of this audit's own setup, but
durable): the harness that both region benchmarks include writes to a
non-configurable `test/result/` with fixed filenames (`pic_hcc.lum`,
`pic_hcc.ele.h5`, `pic_hcc.pro.h5`), so two concurrent runs of the harness — or
of the two benchmark scripts, or of two modes of the diagnostics benchmark —
collide, and the observed failure mode is an opaque HDF5 error raised at
*finalize*, after the entire measured run.
Mechanism: `input.result_dir = joinpath(@__DIR__, "..", "result")` is a literal
in the config block with no `ENV` override; the moment observer opens its file
`"w"` at prepare and `"r+"` at flush/finalize.
Repro (measured, once, on this shared box): the first
`OCTOPUS_DIAGNOSTIC_BENCHMARK_MODE=both` run — whose output path resolved,
through this unit's symlinked run-root, to the shared `<repo>/test/result/` —
died with
`ERROR: LoadError: unable to determine if …/result/pic_hcc.ele.h5 is accessible
in the HDF5 format (file may not exist)` at
`_finalize_line_observers!` (Tasks.jl:890). Controls run afterwards: HDF5 create
+ reopen in that same directory works (`OK`); a minimal `StrongStrongTask` with a
`ScheduledObserver(MomentObserver(...; capacity=3))` creates and finalizes its
file normally (`probe_moment_observer_file.jl`); and the identical benchmark
invocation with a **private** output directory passes
(`electron_moment_bytes = 7952`, `proton_moment_bytes = 7952`,
`luminosity_bytes = 151`, exit 0). **Conclusion: not a defect in the region's
scripts** — a shared-path collision with another agent — but the harness's fixed
output location is the seam that makes it possible, and the failure surfaces
after the measurement rather than before it.

---

## 7. Hypothesis (c) — README accuracy, entry by entry

All 20 region scripts have a README entry (`crossing_luminosity_anchor.jl` and
`tune_estimator_calibration.jl` gained theirs in this audit window, closing
U21-1). Every documented run command was executed (modulo the run-root path
substitution described in §1, which changes only `@__DIR__`); **all of them
work**. Drift found:

| entry | drift | lead |
|---|---|---|
| Beam Optics Interface Consistency | claims "CPU/CUDA agreement"; no cross-backend comparison exists | U25-7 |
| Tracking Backend Consistency | describes the pre-U21-5 11-kind line; no mention of 29-kind coverage or the tripwire; omits `OCTOPUS_CONTRACT_SEED` | U25-13 |
| PIC Option Consistency and Cost | outputs list omits `pic_option_<tag>.lum`; override list omits `OCTOPUS_OPT_NPART_E/_P`, `OCTOPUS_OPT_BATCH_MODE`, `OCTOPUS_OPT_CUDA_ASYNC` | U25-1, U25-8 |
| Strong-Strong PIC Extreme CUDA Benchmark | `result/pic_extreme_summary.tsv` undocumented | U25-8 |
| Strong-Strong Diagnostic Output Benchmark | no outputs documented at all (2 result files + 3 harness files) | U25-8 |
| Counter RNG | CSV destination unstated (and it moved this window); no pointer to the KAT gate that is the actual generator anchor | U25-8, U25-2 |
| soft_gaussian_pic_comparison | CUDA requirement unstated (script header has it, README does not) | U25-9 |
| moment_observer_backend_consistency | CUDA requirement unstated | U25-9 |
| tracking_context_policy_consistency | CUDA-only checks presented as unconditional | U25-10 |
| crossing_luminosity_anchor / tune_estimator_calibration | wrong section, no metric, no outputs | U25-12 |

Entries verified **accurate** against the code, with no drift:
`public_configuration_effectiveness` (the contract's GPU run reported every
capability the entry claims: CPU worker counts, fused CUDA sweep, device-mismatch
rejection, all 7 PIC launch families, sequential + wavefront branches, schedules
and capacities, inherited/inactive reports, pre-mutation rejection),
`strong_strong_pic_cache_backend_consistency` (including the `TSC` and
`LUMINOSITY_DEPOSIT_METHOD` variants, both run),
`strong_strong_gaussian_backend_consistency` (the "which number to read"
paragraph matches the metric names and the criterion `max_allowed_ratio <= 1`
exactly), `strong_strong_observer_plan_consistency`,
`strong_strong_diagnostics_consistency`, `strong_strong_luminosity_schedule_output`,
`tracking_task_turn_update`, `pic_option_consistency_summary`,
`pic_slice_boundary_jitter` (its quoted first-run headline — outer boundaries
0.13–0.17 σ_z, internal ~0.003 σ_z under `:equal_area` — matches the recorded
`result/pic_slice_boundary_jitter.tsv` at the default settings: 0.1337/0.1328 and
0.1642/0.1691 outer, 0.00336 internal; the quoted improvement ratios 1.6×/13×
read 1.50×/11.0× in that file, inside the ~13 % sampling error of a 64-turn
standard-deviation ratio).

---

## 8. Hypothesis (e) — counter_rng_validation.jl and the Random123 KAT

Answer: **it does not validate against the official Random123 known-answer
vectors, and it does not compare against a second implementation either.** It
computes moments, two correlations, three tail fractions, and three
self-consistency booleans from the *same* production functions
(`counter_normal`/`counter_uniform01` or their splitmix twins). The KAT gate
exists elsewhere — `test/runtests.jl:3873`, three upstream `philox4x32 10`
`kat_vectors` (all-zero, all-ff, and the π-digit vector), added in response to
U15-1 — and it is not referenced from this script or from the README. See
U25-2 for the measured consequence (a bumpless Philox passes) and U25-3 for the
threshold-scaling defect found alongside it.

---

## 9. Clean list — what audits sound, and the evidence

1. **Every GPU leg in the region runs and passes.** Twelve scripts, gates forced
   on by their real names, all `EXIT 0` with the metrics in §3. In particular the
   U21-5 coverage extension — 11 hand-picked kinds → all 29 declaring kinds,
   including the whole magnet family, solenoid, patch, aperture and every thin
   element — **compiles and agrees on device**: CPU/GPU `max_abs_error =
   1.665e-16` over 10 000 particles × 2 turns, unchanged before and after the
   mid-unit solenoid fix `4ecc030`.
2. **The declaration↔coverage tripwire is real and fires**, with the exact error
   message, before any contract is built (§4.1).
3. **CPU/CPU bitwise determinism holds**: `max_abs_error = 0.0` at 4 threads,
   which is the property the header claims (particle-indexed counter RNG, not
   thread-scheduling-dependent).
4. **The U21-9 fixes to `pic_option_consistency_summary.jl` are correct and
   effective.** The per-beam regrouping works: the coordinate table now prints
   beam 1 and beam 2 separately with their own σ (`gpu` arm: 4.2e-15 / 5.4e-14;
   `node` arm: 1.7e-2 / 2.5e-2 for beam 1 and 5.7e-3 / 1.2e-2 for beam 2). The
   "SKIPPED (no baseline run found)" line prints, and the no-baseline path
   degrades gracefully rather than erroring (`vcat()` of an empty row list is a
   valid empty array; the summary TSV is written header-only).
5. **The U19-8 output-discipline fix works**: `counter_rng_validation.jl` writes
   its CSV under `result/`, `mkpath`s it, and leaves `validation/` untouched
   (verified: the only file produced was
   `result/counter_rng_validation_summary.csv`).
6. **CPU/GPU parity of the whole PIC option pipeline**: the `gpu` arm of
   `pic_option_consistency.jl` reproduces the CPU `base` arm to
   `rms_dx/σ_x = 4.2e-15` and `rms_dy/σ_y = 5.4e-14` per particle after 6 turns,
   and its luminosity series to `2.2e-15` relative.
7. **`crossing_luminosity_anchor.jl` reproduces its physics**: head-on
   L = 7.94e22, 12.5 mrad half-crossing L = 2.95e22, ratio **R_code = 0.37195**
   against the Piwinski continuous **0.37137** and the 15-quantile-slice discrete
   **0.36926** (code/discrete = 1.0073); ideal crabs restore **R = 1.0** exactly.
   φ = 2.5. The discrete reference is internally consistent with the continuous
   one (`E[exp(−a Δz²)] = 1/sqrt(1+φ²)` for Δz of variance 2σ_z²), which I
   re-derived.
8. **`strong_strong_luminosity_schedule_output.jl` still pins the exact rows**
   including the evaluated `NaN` and the collision-column header — and it does so
   *through* the in-flight F2 rewrite of the luminosity prepare/commit path, which
   is a useful independent confirmation that `4ecc030` did not disturb the
   scheduled-output contract.
9. **The `:skipped`-never-passes discipline holds** for the three contract
   scripts: each honours `OCTOPUS_REQUIRE_GPU_CONTRACT`, and
   `public_configuration_effectiveness.jl` errors only on `:failed` exactly as
   its README entry says.
10. **Determinism hygiene**: every script in the region that draws random numbers
    seeds explicitly — `set_global_rng!(seed=…, method=:philox)` in
    `pic_option_consistency`, `pic_slice_boundary_jitter`,
    `crossing_luminosity_anchor`, `beam_optics_interface_consistency`,
    `tracking_context_policy_consistency`, the contract scripts via
    `contract.seed`; the two Julia-RNG exceptions are seeded too
    (`MersenneTwister(0x4f63746f707573)` in `moment_observer_backend_consistency`,
    `MersenneTwister(20260728)` in `tune_estimator_calibration`).
11. **Benchmark provenance is complete where it exists**:
    `result/pic_extreme_summary.tsv` records git commit, Julia version, GPU name,
    driver and runtime versions, precision, turn count, macroparticle counts,
    grid, deposit methods (requested *and* resolved), batching, cache settings,
    and requested-vs-resolved thread counts for all seven CUDA PIC families.
12. **`tune_estimator_calibration.jl` reproduces its calibration**: 500 trials,
    median |ΔQ| = 4.8e-6, p95 = 6.5e-6, max = 7.8e-3 — i.e. the estimator is
    ~5e-6 accurate except for a small failure tail, which is the number the
    coherent-mode scripts rely on when they quote agreement "to ~1e-5 in tune".
13. **Structural guards that do bite**: `strong_strong_pic_extreme_benchmark.jl`
    refuses fewer than 20 turns; `strong_strong_diagnostics_benchmark.jl` rejects
    an unknown mode; `LongitudinalSlicing`/solver constructors reject the option
    values these scripts pass through, so `pic_option_consistency.jl` does not
    need its own enumeration.

---

## 10. Not checked, and why

- **Absolute performance numbers.** The box carried 16–19 concurrent audit
  agents and one shared GPU throughout. The extreme benchmark's
  `steady_last_ten_mean = 0.270 s` at 2.56M/1.0M/128²/15 slices is consistent
  with the recorded ~0.3 s/turn production point, but it is **not** a clean
  measurement and must not be entered in the benchmark history.
- **Default-size runs of the two long scripts.** `pic_option_consistency.jl` was
  run at 6 turns × 2 000 particles per arm rather than the default 200 × 50 000
  (U21-10 measured 0.34–1.45 s/turn per arm), and `pic_slice_boundary_jitter.jl`
  at 20 000 particles × 8 turns rather than 100 000 × 64. Both were exercised for
  correctness and exit status; the README's quoted first-run headline for the
  jitter script was instead checked against the committed
  `result/pic_slice_boundary_jitter.tsv` produced at the default settings.
- **`OCTOPUS_SOLVER=gaussian` mode of the diagnostics benchmark** and the
  `luminosity`, `luminosity_io`, `moments` modes individually: only `baseline`
  and `both` were run (they bracket the feature matrix — nothing enabled and
  everything enabled).
- **Whether `PublicConfigurationEffectivenessContract` genuinely covers every
  capability its README sentence claims** was taken from the contract's own
  metrics dictionary (all `*_effective`/`*_rejected` keys true, `cuda_status =
  passed`) rather than by auditing `Contracts.jl` — that file is another unit's
  region.
- **`test/runtests.jl:3873`'s own hand-copy of the Philox driver loop** (noted
  under U25-2) is a seam into the test suite and was left to the auditor.
- **The mid-unit source changes** (`4ecc030` solenoid convergence half) were not
  audited; only their effect on this region's GPU result was re-measured.
