# U4 Audit Report — `src/contracts/Contracts.jl` (HEAD `7de4d81`)

Reading unit U4 of the comprehensive audit protocol. Region: **the whole of
`src/contracts/Contracts.jl`, lines 1–2715**. Prior pass on this region:
`docs/history/comprehensive_audit_2026_08_05_unit_reports/U3_report.md`
(commit `6a3f39a`); 63 commits have landed since, 264 insertions / 93 deletions
in this file.

---

## 1. Provenance

### Read (every line)

`src/contracts/Contracts.jl` 1–2715, in six Read passes (1–400, 400–800,
800–1200, 1200–1600, 1600–2000, 2000–2399, 2399–2715). Nothing skimmed.

Collaborator files read for verification (not audited):
`src/knowledge/Knowledge.jl` 173–200, 464–475, 540–560, 610–630, 920–930;
`src/registry/Registry.jl` 1–135; `src/tasks/strongstrong/interface.jl`
1500–1810 and 2255–2300; `src/tasks/strongstrong/gaussian.jl` 15–75;
`src/tasks/BeamObservers.jl` 826–885; `src/tasks/BPMObserver.jl` 300–330;
`test/runtests.jl` (grep + excerpts 1880–1945, 2055–2090, 3725–3800,
4140–4160, 4240–4285, 8165–8200); `validation/` listing + greps;
`AGENTS.md` "Hard-Won Rules"; `docs/comprehensive_audit.md` "Phase 7" and
"Measured Lessons"; the U3 report; `git diff 6a3f39ab HEAD -- src/contracts/Contracts.jl`.

### Executed (this host: RTX 4500 Ada, CUDA 13.0, functional)

All probes live under
`/tmp/claude-320114/-cfs-ad-dxu/37c712a3-734a-4817-a05e-4c9e12cabcef/scratchpad/audit/`
(session scratch; **no repository file was modified**).

| probe | what it measured |
|---|---|
| `p1_enumerations.jl` | contract type tree vs exports; Poisson-solver tree vs `_solver_contract_types()`/probes; symplecticity declarations vs cases |
| `p2_elemparam.jl` | full branch accounting of `validate(ElementParameterEffectivenessContract)`; staleness of `inactive`/`probes` |
| `p3_solveropts.jl` | every `(solver, option)` category/consumer and the contract route it takes; `_solver_contract_receipt_carries` behaviour |
| `p4_misc.jl` | `:cuda_pic_launch` receipt branch; `validate(...; kwargs...)`; ghost-solver injection into the solver tree |
| `p5_circular.jl` | `:solver_runtime` receipt content on CPU and CUDA; kernel sharing; `StrongStrongTask` defaults; BPMObserver schema↔report |
| `p6_lists.jl` | category enumeration; `DEFAULT_INACTIVE_SOLVER_OPTIONS` staleness; deposit-method enumeration; symplecticity coverage; knob cleanup list; PTC table/generator |
| `p7_symbolsweep.jl` | extension of the parameter contract to Symbol-valued parameters (the class it cannot see) |
| `p8_focus.jl` | `sbend.fringe` at the shipped probe vs a probe that can act; `misalign_convention` value validation per kind |
| `p9_nan.jl` | NaN-poisoned aperture baseline; control with a generous aperture |
| `p10_perturb.jl` | `_perturb_param` magnitudes; the 29 silently-rejected perturbations and why |
| `p11_live.jl` | live run of all 11 contracts (12 configurations) with an RNG-leak sentinel |
| `p12_t1.jl` | `PublicConfigurationEffectivenessContract` at `-t1` |

Live run at `-t4` with a functional CUDA device — **all 12 configurations
`:passed`**, and the `0xDEADBEEF` sentinel showed **no RNG leak from any
contract** (U3-1 verified closed):

```
SymplecticityContract                        passed
ElementParameterEffectivenessContract        passed   353 checked, 0 kinds without a probe
PTCConsistencyContract                       passed   MAD-X 5.03.06, 55 cases, worst 5.0e-13
KnobEffectivenessContract                    passed
PublicConfigurationEffectivenessContract     passed   cuda_status=passed, families all 7
SolverOptionEffectivenessContract            passed   68 CPU / 10 CUDA-only / 2 launch surfaces
StrongStrongGaussianBackendConsistency       passed
StrongStrongPICBackendConsistency            passed
StrongStrongPIC(green_cache=:none,seq)       passed
HighEnergyWeakStrongLimitContract            passed
CoherentModePhysicsContract(:pic)            passed
CoherentModePhysicsContract(:gaussian_pic)   passed
```

---

## 2. Leads

### LEAD U4-1 [Medium, confidence high] src/contracts/Contracts.jl:1963-1967 (probe) → :2125 (decision)
Claim: the `:aperture` probe produces an all-NaN baseline, so all 11 aperture parameters counted in `checked` are decided by a NaN comparison that can only ever say "the parameter moved the map" — the aperture half of `ElementParameterEffectivenessContract` cannot fail.
Mechanism: the probe comment says the tight limits mean "the probe particle sits outside and is killed, so perturbing any of them changes the map". A killed particle's six coordinates are `NaN`. The decision at :2125 is `maximum(abs, moved .- baseline) <= contract.atol` with `atol = 0.0`; `NaN <= 0.0` is `false`, so the pair is *not* pushed to `ignored` and is scored effective. The perturbed map is NaN too, so the difference is NaN for every parameter regardless of whether the parameter is read. This makes `aperture.{x_limit, y_limit, dx, dy}` plus all seven placement parameters unfalsifiable. The control proves the comparison itself works: with a generous aperture (particle survives, map is the identity) the contract *does* fail, naming `aperture.dx, aperture.dy, aperture.x_limit, aperture.y_limit`.
Repro:
```
julia --startup-file=no --project=. -e '
using Octopus; O=Octopus; u=(2.3e-3,4.1e-4,-1.7e-3,-3.2e-4,1.5e-3,9.0e-4)
ap = Dict{Symbol,Any}(pairs(O.DEFAULT_ELEMENT_PARAM_PROBES[:aperture]))
println(collect(O.compile_runtime(O.ApertureSpec(; ap...))(u...)))'
```
should print `[NaN, NaN, NaN, NaN, NaN, NaN]` (it does). And the control:
```
julia --startup-file=no --project=. -e '
using Octopus; p = copy(Octopus.DEFAULT_ELEMENT_PARAM_PROBES)
p[:aperture] = (shape=:ellipse, x_limit=1.0, y_limit=1.0, dx=1.0e-5, dy=2.0e-5)
r = validate(ElementParameterEffectivenessContract(probes=p)); println(r.status, " ", r.message)'
```
prints `failed declared but not consumed: aperture.dx, aperture.dy, aperture.x_limit, aperture.y_limit`.

---

### LEAD U4-2 [Medium, confidence high] src/contracts/Contracts.jl:2116-2117 and :2122, message at :2135-2137
Claim: of the 501 declared element parameters (`ParamMeta` entries across all registered specs), 353 are checked, 36 are documented-inactive, and **112 are silently dropped** — neither counted in `checked` nor reported anywhere — while the contract's message reads as a completeness claim: "every declared element parameter reached the map (353 checked, 0 kinds without a probe)".
Mechanism: two `continue`s drop a parameter before `checked += 1` (:2124) and leave no trace in `metrics`. (i) `:2117` — `_perturb_param` returns `nothing` for every `Symbol`, every `tracking_method`, and every value that is not `Bool`/`Symbol`/`Tuple`/`Integer`/`Real`; that is **83** parameters, including `misalign_convention` on all 25 kinds, `fringe` on quadrupole/sextupole/octupole/multipole/sbend, `sbend.bend_model`, `aperture.shape`, `patch.convention`, `gaussian_strong_beam.slice_method`, `xy_coupling.mode`. (ii) `:2122` — a perturbation the constructor rejects is `continue`d with the comment "a rejected value is consumed by definition"; that is **29** parameters (see U4-3, where ~15 of them are genuine holes rather than validated sugar). `metrics` reports only `:checked`, `:ignored`, `:skipped_kinds`, `:broken_kinds` — there is no `:unperturbable` or `:rejected` count, so the discrepancy is invisible to a reader and to the `runtests.jl` pins (which assert `checked > 200`, `skipped_kinds == 0`, `broken_kinds == 0`). AGENTS.md: "do not report an unrun check as passed".
Repro: `scratchpad/audit/p2_elemparam.jl` — re-runs the contract's own loop with full accounting; prints `checked = 353`, `unperturbable = 83`, `rejected = 29`, and the contract's own message beside them.

---

### LEAD U4-3 [Medium, confidence high] src/contracts/Contracts.jl:2061-2072 (`_perturb_param`)
Claim: `_perturb_param`'s magnitude and type dispatch make ~15 declared parameters permanently unverifiable, and the "rejected ⇒ consumed" reasoning at :2122 is wrong for all of them.
Mechanism: three distinct sub-defects.
- **1 metre / 1 radian placement perturbations.** `_PLACEMENT_PARAMS` (Knowledge.jl) declares `x_offset=ParamMeta(default=0, unit="m")` — the *integer* `0`. `_perturb_param`'s `current isa Integer` branch (:2069) returns `Int(current)+1`, so every placement parameter absent from a kind's probe is perturbed by **1 m** or **1 rad**. Seven of these throw `DomainError` inside the map and are silently dropped: `sextupole.y_offset`, `octupole.y_offset`, `multipole.y_offset`, `sbend.y_offset`, `sbend.x_pitch`, `sbend.y_pitch`, `solenoid.x_pitch`. They are not "consumed by definition"; a 1e-3 perturbation moves the sbend map by 6.8e-4 (y_offset), 4.1e-5 (x_pitch), 4.7e-5 (y_pitch) — i.e. they are perfectly checkable at a physical amplitude.
- **`curved` never checked on any kind.** `curved`'s schema default is the *float* `0.0`, not `false`, so `_perturb_param` takes the `Real` branch (:2070) and returns `0.13`; the constructor then raises `InexactError: Bool(0.13)`. `drift.curved`, `sbend.curved`, `solenoid.curved` are therefore never verified — the parameter that audit F17 ("`curved=false` finally means straight") was about.
- **`integrator_order` never checked on five kinds.** `2 -> 3` is rejected (`must be one of (2, 4)`), so `quadrupole/sextupole/octupole/multipole/sbend .integrator_order` are all silently dropped — while `(:drift, :integrator_order)` sits in `DEFAULT_INACTIVE_ELEMENT_PARAMS` with a reason, which reads as a claim that the parameter *is* checked on the kinds that lack an exemption.
Repro: `scratchpad/audit/p10_perturb.jl` — prints the schema default type and the perturbation for every placement parameter, then every one of the 29 rejections with its exception message, then the three sbend deltas at a 1e-3 perturbation.

---

### LEAD U4-4 [Medium-Low, confidence high] src/contracts/Contracts.jl:1942-1945 (`:sbend` probe)
Claim: `sbend.fringe` is bitwise inert at the probe the contract ships, violating the probes' own stated design rule, and the Symbol blind spot (U4-2) guarantees nobody will ever be told.
Mechanism: the docstring at :1925-1927 states "`probes` gives the base keywords per kind, chosen so conditional parameters are in a configuration where they can act: `va` needs a soft-edge fringe enabled, `wedge_coeff` needs both a pole-face angle and a quadrupole component." The `:sbend` probe sets `fringe=:all, highest_fringe=1` and no `va`/`vs` (`SBendSpec` does not even accept `va`/`vs` — it warns "unknown parameter … stored as descriptive metadata only"). At `highest_fringe=1` the multipole fringe is capped below the quadrupole order, so `fringe ∈ {:none, :multipole, :soft_quad, :all}` all compile to a **bitwise identical** map. Raising the probe to `highest_fringe=2` (PTC's own default, which the PTC contract's `sbend_fringe`/`cfbend_fringe` cases use) makes `fringe=:none` differ by 2.04e-7. So the parameter is consumable; the probe cannot reach it. The same sweep also shows `:soft_quad` is inert on quadrupole/sextupole/octupole/multipole (identical to `:all` at their probes) while `:none`/`:multipole` are not.
Repro:
```
julia --startup-file=no --project=. -e '
using Octopus; O=Octopus; u=(2.3e-3,4.1e-4,-1.7e-3,-3.2e-4,1.5e-3,9.0e-4)
sb = Dict{Symbol,Any}(pairs(O.DEFAULT_ELEMENT_PARAM_PROBES[:sbend]))
b  = collect(O.compile_runtime(O.SBendSpec(; sb...))(u...))
for f in (:none,:multipole,:soft_quad)
  m = collect(O.compile_runtime(O.SBendSpec(; merge(sb, Dict{Symbol,Any}(:fringe=>f))...))(u...))
  println(f, " ", maximum(abs, m .- b)) end'
```
prints `0.0` three times; add `:highest_fringe=>2` to `sb` and `:none` becomes `2.0395334094725284e-7`.

---

### LEAD U4-5 [Medium, confidence high] src/contracts/Contracts.jl:2444-2454
Claim: the U3-8 repair to the `:cuda_pic_launch` branch of `_solver_contract_receipt_carries` is vacuous for **both** options that actually take that branch, so the per-option receipt claim is still receipt-existence; and the same branch carries a latent `FieldError`.
Mechanism: `(name === :threads || name === :blocks) || return true` (:2451) short-circuits to `true` for every option name other than the two literals. The only options in the whole schema whose declared `consumer` is `:cuda_pic_launch` are `PICPoissonSolver.backend_configurations` and `GaussianPICPoissonSolver.backend_configurations` — neither is `:threads` nor `:blocks`, so both take the unconditional `return true` exactly as before the fix. (There is no option named `:threads` or `:blocks` anywhere in `solver_option_schema`, so the comparison arm at :2452 is dead code.) Separately, :2452 does `getproperty(r.values, name)` guarded only by `haskey(r.values, :threads)` at :2450; a `:cuda_pic_launch` receipt carrying `(family, threads)` but not `blocks` would make the contract **throw** `FieldError` rather than fail. Mitigation, unchanged from U3-8: the dedicated launch-surface check at :2665-2702 does verify `threads == contract.cuda_threads` across all receipts for both solvers, so the *configuration* is genuinely proven — but the per-option "reached a receipt named by its consumer" claim at :2651-2655 is not.
Repro:
```
julia --startup-file=no --project=. -e '
using Octopus; O=Octopus
struct R; consumer::Symbol; values; end
r = [R(:cuda_pic_launch, (family=:kick, threads=999))]
println(O._solver_contract_receipt_carries(r, :cuda_pic_launch, :backend_configurations, :never_published))
try O._solver_contract_receipt_carries(r, :cuda_pic_launch, :blocks, 7) catch e; println(sprint(showerror,e)) end'
```
prints `true` then `FieldError: type NamedTuple has no field blocks`.

---

### LEAD U4-6 [Medium, confidence high] src/contracts/Contracts.jl:2432-2443 with :2552-2555 / :2651-2655
Claim: for options whose declared consumer is `:solver_runtime`, "the value reached a runtime consumer" is proven by reading back a receipt that is a verbatim dump of the object under test — the check's pass is guaranteed by construction. This is hypothesis (a) in the file's most load-bearing contract.
Mechanism: `_record_solver_configuration!` (interface.jl:2275-2280) emits `(solver=…, configuration=solver_configuration(solver))`, and it is called from `_strong_strong_collide!` **before** `_with_solver_execution_configuration` and before any backend dispatch. `_solver_contract_receipt_carries(…, :solver_runtime, name, value)` then reads `getproperty(cfg, name)` — the value the contract itself just set on the constructor. Nothing about a consumer having read it is involved. The one option this bites today is `GaussianPoissonSolver.batch_mode` (`category=:performance`, `consumer=:solver_runtime`, `supported_backends=(CUDABackend,)`), which is precisely the defect the contract's own docstring cites at :2315-2316: "a CUDA-only `batch_mode` on the soft-Gaussian solver was inactive on CPU with no warning anywhere". If the CUDA soft-Gaussian route stopped reading `batch_mode` tomorrow, the execution half's two assertions — "must not move the observable" (satisfied by an ignored option) and "must appear in a receipt named by its consumer" (satisfied by the dump) — would both still hold. Side observation from the same probe: no **CPU** option takes the receipt route at all, because `_solver_contract_observable` calls `collide!` directly and bypasses `_strong_strong_collide!`, so zero `:solver_runtime` receipts are emitted on the CPU half; `_solver_contract_receipt_carries` is exercised only by the 10 CUDA-only options.
Repro: `scratchpad/audit/p5_circular.jl` section G — runs the Gaussian solver with `batch_mode=:sequential` through `_solver_contract_cuda_observable`, prints `receipt.configuration.batch_mode = sequential` and `_solver_contract_receipt_carries(..., :solver_runtime, :batch_mode, :sequential) = true`, and prints `0` `:solver_runtime` receipts from the CPU observable.

---

### LEAD U4-7 [Medium, confidence high] src/contracts/Contracts.jl:2459-2471 vs :2338-2339
Claim: the new solver-enumeration tripwire guards `contract.probes`, but the sweep iterates the hardcoded `_solver_contract_types()`. The two sets are different, so the natural response to a firing tripwire (add a probe entry) makes the contract pass while the new solver is still never swept.
Mechanism: the guard's derived set is `{T : T <: AbstractPoissonSolver, !isabstracttype(T), parentmodule(T) === Octopus}` and its obligation is `haskey(contract.probes, nameof(T))`. `_validate_solver_options` at :2495 and :2583 loops over `_solver_contract_types()`, a four-element hand-written tuple. `probes ⊇ derived` does not imply `_solver_contract_types() ⊇ derived`. Demonstrated by injecting an Octopus-defined solver with a probe entry: the contract returns `:passed` with the unchanged "68 on CPU, 10 CUDA-only options, 2 launch surfaces" while the ghost solver's schema was never read. Two smaller shape notes on the same guard: `subtypes` is **non-recursive**, so a future intermediate abstract solver type would hide its concrete leaves (`isabstracttype(T) && continue` skips the intermediate without descending — `Registry.jl` uses `_subtypes_recursive` for the same tree); and `parentmodule(T) === (@__MODULE__)` means the guard can never fire for a test-defined solver, so its own pinning test has to delete a probe entry instead.
Repro:
```
julia --startup-file=no --project=. -e '
using Octopus; O=Octopus
@eval O struct AuditGhostSolver <: AbstractPoissonSolver end
p = copy(O._default_solver_option_probes()); p[:AuditGhostSolver] = NamedTuple()
println(validate(SolverOptionEffectivenessContract(probes=p)).status)     # passed
println(validate(SolverOptionEffectivenessContract()).status)'            # failed
```

---

### LEAD U4-8 [Medium, confidence high] src/contracts/Contracts.jl:1276-1290 with :1172-1243
Claim: the declaration↔case tripwire constrains exactly **one** registered kind, and fifteen kinds whose declared tracking method is `Symplectic6DMap` have no symplecticity case at all. The tripwire's authoritative set is a hand-written declaration list that only one element populates, so its discriminating power is 1 of 12 cases.
Mechanism: the tripwire's derived set is `{kind : SymplecticityContract ∈ element_meta(kind).contracts}`. Measured: that set is exactly `[:solenoid]`. The other eleven cases in `_symplecticity_contract_cases()` (Linear6D, CrabDispersion, MomentumDispersion, XYCoupling, ThinCrabCavity, ChromaticityKick, ThinStrongBeam×3, GaussianStrongBeam) correspond to kinds that do **not** declare the contract, so removing any of them from the list would not trip the wire. A new symplectic element added the way the existing 21 were — declaring only `ElementTrackingBackendConsistencyContract` — is invisible. Measured coverage against the structural set: of the 22 registered kinds declaring `Symplectic6DMap`, 7 have a case (`chromaticity_kick, crab_dispersion, linear6d, momentum_dispersion, solenoid, thin_crab_cavity, xy_coupling`) and **15 do not** (`drift, hkicker, kicker, marker, multipole, octupole, quadrupole, sbend, sextupole, thin_dipole, thin_multipole, thin_quadrupole, thin_rf_cavity, thin_sextupole, vkicker`). The lattice magnets among them are covered against PTC, which is a different claim (agreement with an external code, not `‖JᵀSJ − S‖ ≤ tol`); the thin kickers, marker and RF cavity are covered by neither. Note the underlying declaration is itself validated only by `validate_element_metadata`'s "is this a subtype of `AbstractContract`" check (Knowledge.jl:926) — the circular validator the protocol records as catching 1 of 13 injected defects. Deriving the case obligation from `Symplectic6DMap ∈ meta.tracking_methods` instead of from `meta.contracts` would make the tripwire bite.
Repro: `scratchpad/audit/p6_lists.jl` section O — prints the declaring set (`[:solenoid]`), the 7 covered kinds and the 15 uncovered ones.

---

### LEAD U4-9 [Low-Medium, confidence high] src/contracts/Contracts.jl:867-879 with metrics at :905-915
Claim: `StrongStrongPICBackendConsistencyContract` reports three named checks as passed with nothing compared, for public parameter choices its own docstring advertises.
Mechanism: `cache_reuse_ok = contract.green_cache != :slice_pair || cpu_history[1] > 0` (:879) is unconditionally `true` for any other cache mode, and `cache_history_ok = cpu_history == gpu_history` reduces to `(0,0,0) == (0,0,0)` when neither side has a cache; `pair_trace_expected = contract.batch_mode == :wavefront` (:867) makes `pair_luminosity_rel = 0.0` and `pair_luminosity_ok = true` for `:sequential`. Measured with `green_cache=:none, batch_mode=:sequential` on a live CUDA run: `cache_histories_match = true`, `cache_reuse_observed = true`, `cpu_cache_history = (0,0,0)`, `gpu_cache_history = (0,0,0)`, `slice_pair_luminosity_records_compared = 0`, `slice_pair_luminosity_rel_error = 0.0`, `slice_pair_luminosity_passed_tolerance = true`. `:cache_reuse_observed = true` with zero caches is the misreport AGENTS.md's rule is about; the honest values are `:not_applicable` / `:skipped`. Two smaller items in the same `validate`: the parameter guards at :787-798 sit **after** the CUDA availability gate at :780-786, so `n_particles <= 0` returns `:skipped` rather than the diagnosis on a CPU-only host; and `green_cache`, `batch_mode`, `slice_pair_green_min_ratio`, `slice_pair_green_growth` get no contract-level validation while `deposit_method` and `luminosity_deposit_method` do (the solver constructor does throw on a bad symbol, so this is loud today, not silent).
Repro:
```
julia --startup-file=no --project=. -e '
using Octopus
r = validate(StrongStrongPICBackendConsistencyContract(green_cache=:none, batch_mode=:sequential))
println(r.status); for k in (:cache_histories_match,:cache_reuse_observed,:cpu_cache_history,
  :slice_pair_luminosity_records_compared,:slice_pair_luminosity_passed_tolerance)
  println(k, " = ", r.metrics[k]) end'
```

---

### LEAD U4-10 [Low-Medium, confidence high] src/contracts/Contracts.jl:321-322 with :344-348 and :351-354
Claim: on a single-threaded Julia the `PublicConfigurationEffectivenessContract`'s worker-invariance comparison executes zero times, yet the metrics report it as measured and passed.
Mechanism: `worker_sweep = unique((1, min(2, Threads.nthreads(:default)), Threads.nthreads(:default)))` collapses to `[1]` at one thread. The comparison at :344-348 lives in the `else` branch of `rep_cpu === nothing`, so with one sweep element it never runs; `cpu_coordinate_error` stays at its initialiser `0.0` and :351-354 unconditionally publish `:cpu_worker_coordinate_max_abs_error => 0.0` and `:cpu_worker_effective => true`. Measured at `-t1` on this host: `status = passed`, `cpu_workers_tested = [1]`, `cpu_worker_coordinate_max_abs_error = 0.0`, `cpu_worker_effective = true`. This is the same shape as Measured Lesson 5 (the thread-invariance pin measured outside the regime it claims). The CI gate runs at `--threads=4` so the suite is not currently affected; `validate()` is public API and a user running single-threaded gets a claim that was not measured.
Repro: `julia --startup-file=no --project=. -t1 -e 'using Octopus; r=validate(PublicConfigurationEffectivenessContract()); println(r.status, " ", r.metrics[:cpu_workers_tested], " ", r.metrics[:cpu_worker_coordinate_max_abs_error], " ", r.metrics[:cpu_worker_effective])'` → `passed [1] 0.0 true`.

---

### LEAD U4-11 [Low-Medium, confidence high] src/contracts/Contracts.jl:1351-1371 with docstring :1310-1317
Claim: the "analytic weak-strong reference" that `HighEnergyWeakStrongLimitContract` holds the soft-Gaussian solver to at 2e-14 is not analytic and not independent — it calls the same three functions the production soft-Gaussian collision calls, so a defect in the kick cancels exactly and the sharp half of the contract cannot detect it.
Mechanism: `_wsl_weakstrong_reference!` calls `_slice_collision_order`, `_slice_transverse_moments` and `_slice_slice_gaussian_kick!`. Each has exactly **one** method in the package (`slicing.jl:500`, `slicing.jl:599/609`, `gaussian.jl:59`), and `_gaussian_collide_pair!` (`gaussian.jl:15-56`) calls the same three. The reference differs only in loop structure — one direction, source moments recomputed from an unmodified source. What the contract genuinely proves is that at infinite source energy the strong-strong scheduling, slice weights, `kbb`, `klum` and drift plumbing reduce to the frozen-source construction, which is real and worth having. What it does not prove, contrary to "the soft-Gaussian solver is held to machine-precision agreement with the analytic weak-strong reference (this is the sharp limit statement)", is anything about `_slice_slice_gaussian_kick!` itself. (The **PIC** half at 8% tolerance *is* a genuine cross-implementation comparison; that half is sound.) This also corrects the prior U3 report's inventory line, which recorded "independent hand-rolled reference kick".
Repro: `julia --startup-file=no --project=. -e 'using Octopus; for f in (:_slice_slice_gaussian_kick!,:_slice_transverse_moments,:_slice_collision_order); println(f, " ", length(methods(getfield(Octopus,f)))); end'` → `1`, `2`, `1`; then `grep -n "_slice_slice_gaussian_kick!" src/tasks/strongstrong/gaussian.jl src/contracts/Contracts.jl` shows the production caller (gaussian.jl:44,50) and the contract's reference (Contracts.jl:1362) reaching the same definition (gaussian.jl:59).

---

### LEAD U4-12 [Medium-Low, confidence high] src/contracts/Contracts.jl:1932-1986 (probes) with :2064
Claim: `misalign_convention` — the MAD-X-vs-Bmad rotation composition order, which the PTC contract's `quad_mis_all` / `cfbend_mis_all` cases exist precisely to pin — is **inert at every shipped probe**, on all 25 kinds, and the Symbol blind spot means the contract cannot even report it as unprobed.
Mechanism: each kind's probe is in one of two states, and neither can show the parameter. (i) No placement offset at all (`drift`, `marker`, `solenoid`, `linear6d`, `patch`, `crab_dispersion`, …): the misalignment wrap is never built, so the convention is inapplicable. (ii) Exactly one offset (`quadrupole`, `sextupole`, `octupole`, `multipole`, `sbend`, `thin_*`, `hkicker`, `vkicker`, `kicker` — all carry `x_offset=1.0e-3` and nothing else): measured `max|madx − bmad| = 0.0`, which is the documented fact stated in the PTC case comments at :1704-1706 — "One rotation at a time cannot distinguish the two composition orders, which agree there". With all six placement degrees of freedom nonzero (the `quad_mis_all` shape) the two conventions differ by **1.294e-4**, so the parameter is perfectly observable; the probes just never reach the configuration where it acts. This violates the same probe design rule as U4-4 ("chosen so conditional parameters are in a configuration where they can act"), and `_perturb_param`'s `current isa Symbol && return nothing` (:2064) guarantees the violation is never counted or reported.
Secondary, LOW: validation of the *value* is deferred to the compile of the misalignment wrap, so `misalign_convention=:MADX` on an offset-less spec is silently stored and accepted (`ArgumentError: misalign_convention must be :bmad or :madx; got :MADX` fires only once an offset is present). That is consistent with the repository's documented deferred-validation pattern for element specs, and the unknown-*keyword* warning added in `3d72e18` covers a different failure mode; noting it, not pricing it.
Repro:
```
julia --startup-file=no --project=. -e '
using Octopus; O=Octopus; u=(2.3e-3,4.1e-4,-1.7e-3,-3.2e-4,1.5e-3,9.0e-4)
m(kw) = collect(O.compile_runtime(O.QuadrupoleSpec(; kw...))(u...))
p1 = (L=0.4,k1=1.7,nst=2,x_offset=1.0e-3)
p2 = (L=0.4,k1=1.7,nst=2,x_offset=1.0e-3,y_offset=-8.0e-4,z_offset=2.0e-3,
      x_pitch=1.0e-3,y_pitch=-7.0e-4,tilt=0.02)
for (n,p) in (("shipped probe",p1),("quad_mis_all",p2))
  println(n, " ", maximum(abs, m(merge(p,(misalign_convention=:bmad,))) .-
                              m(merge(p,(misalign_convention=:madx,))))) end'
```
prints `shipped probe 0.0` and `quad_mis_all 0.00012941829668667508`.

---

### LEAD U4-13 [Low, confidence high] src/contracts/Contracts.jl:180, :200, :310, :639, :683, :779, :1245, :1373, :1576, :1836, :2074, :2459
Claim: every `validate` method takes `; kwargs...` and no method reads it, so any keyword a caller misspells or invents is silently accepted and dropped — the (e) unknown-keyword family, inside the file whose job is to catch it.
Mechanism: the signature is uniform (`function validate(contract::X; kwargs...)`), `kwargs` never appears in any body, and there is no `isempty(kwargs) || throw(...)` guard on the fallback at :180 or anywhere else. `validate(SymplecticityContract(); tolerance=1e-30, this_kwarg_does_not_exist=42)` returns a result byte-identical to the no-kwarg call. Note the contrast the contracts themselves assert: `PublicConfigurationEffectivenessContract` at :366-374 fails if `Beam` silently ignores an unknown keyword; the contract *structs* are `Base.@kwdef` and correctly `MethodError` on an unknown keyword. Only the `validate` entry point is permissive.
Repro:
```
julia --startup-file=no --project=. -e '
using Octopus
a = validate(SymplecticityContract())
b = validate(SymplecticityContract(); tolerance=1e-30, this_kwarg_does_not_exist=42)
println(a.passed == b.passed && a.message == b.message)'
```
prints `true`.

---

### LEAD U4-14 [Low, confidence high, CROSS-FILE SEAM] src/contracts/Contracts.jl:185-198, :1146, :1330, :1497, :2335
Claim: the hand-written `description` method table covers 9 of the 11 concrete contracts; `PTCConsistencyContract` and `ElementParameterEffectivenessContract` fall through to a fallback that returns the empty string rather than erroring, so a reflection consumer gets a silent blank.
Mechanism: `description(T::Type)` in `Knowledge.jl:551-554` returns `meta === nothing ? "" : meta.description`, and contracts have no `ElementMeta`, so `description(PTCConsistencyContract) == ""`. `Knowledge.jl`'s own docstring says "Concrete specs, tracking methods, policies, **contracts**, and analyses should extend this method". `registry_snapshot_markdown` lists contract names only, so this does not currently surface in `docs/registry_snapshot.md` — it surfaces to any agent that calls `description` on a registry contract. Same shape as the two hand lists in U4-7/U4-8: a hand-maintained table that has drifted from the type tree, with a silent fallback instead of a tripwire.
Repro: `julia --startup-file=no --project=. -e 'using Octopus; for T in (PTCConsistencyContract, ElementParameterEffectivenessContract, SymplecticityContract); println(T, " => ", repr(Octopus.description(T))); end'` → the first two print `""`.

---

### LEAD U4-15 [Low, confidence high] src/contracts/Contracts.jl:1543-1545
Claim: `CoherentModePhysicsContract(solver=:gaussian_pic)` — one of the three solver branches the contract's docstring declares, and one it declares *passing* — is executed by no test and no validation script.
Mechanism: `test/runtests.jl:8188/8190` runs `:pic` and `:gaussian` only. No file under `validation/` mentions `CoherentModePhysicsContract`; `validation/coherent_beam_beam_modes.jl` builds a `GaussianPICPoissonSolver` through its own solver factory (`:125`) rather than through the contract. So the branch at :1543-1545 and the docstring's claim "The PIC-based solvers pass" carry no runner. Measured: the branch does pass today (live run, `:passed`, "The gaussian_pic solver reproduces the Vlasov-band coherent-mode Yokoya factor with the sigma mode unshifted"), which is what makes this cheap to close.
Repro: `grep -n "CoherentModePhysicsContract" test/runtests.jl validation/*.jl` → three hits, all in runtests, none with `:gaussian_pic`. `julia --startup-file=no --project=. -e 'using Octopus; println(validate(CoherentModePhysicsContract(solver=:gaussian_pic)).status)'` → `passed` (~1 min).

---

### LEAD U4-16 [Low, confidence high] src/contracts/Contracts.jl:1273
Claim: the Lorentz quasi-symplecticity criterion uses two tolerances hardcoded in the function body (`1.0e-10`, `2.0e-7`) that no field of `SymplecticityContract` governs, so the contract's declared `default_tolerance` knob does not reach half of what the contract checks.
Mechanism: `lorentz_passed = inverse_residual <= 1.0e-10 && determinant_error <= 2.0e-7`. `SymplecticityContract` declares `step`, `default_tolerance` and `lorentz_angle`; `default_tolerance` is applied as `max(case.tolerance, contract.default_tolerance)` only to the twelve case residuals. A caller tightening `default_tolerance` to probe a regression gets no change in the Lorentz half, and the two literals are not documented in the struct's docstring the way `default_tolerance` is (:1137-1142). Same family as U3-2 (fixed): a tolerance whose relationship to the declared knobs is not stated.
Repro: `julia --startup-file=no --project=. -e 'using Octopus; a=validate(SymplecticityContract()); b=validate(SymplecticityContract(default_tolerance=1e-16)); println(a.metrics[:lorentz_inverse_residual] == b.metrics[:lorentz_inverse_residual], " ", b.passed)'` — the Lorentz metrics and their pass/fail are unchanged by the knob.

---

### LEAD U4-17 [Low, confidence high] src/contracts/Contracts.jl:1987-2037 and :2257-2288
Claim: neither exemption table has a staleness tripwire. Both are clean today (measured), but a `(kind, parameter)` or `(solver, option)` pair that no longer exists silently excuses nothing, and — the direction that matters — an entry whose parameter later becomes genuinely ignored keeps excusing it forever with no signal.
Mechanism: `validate(::ElementParameterEffectivenessContract)` at :2114 does `haskey(contract.inactive, (meta.kind, key)) && continue` and `_validate_solver_options` at :2503 does the same, with no reverse pass asserting that every declared exemption was actually consulted and that the exemption is still load-bearing. The `runtests.jl` control at 1904-1910 covers exactly one entry (`drift.nst`) by emptying the whole table. Measured today: 0 of 36 element pairs stale, 0 of 10 solver pairs stale, and 0 stale entries in `DEFAULT_ELEMENT_PARAM_PROBES`. The tripwire shape Measured Lesson 4 asks for is "every entry in `inactive` must be a pair that WOULD be reported without it".
Repro: `scratchpad/audit/p2_elemparam.jl` (element table, prints `0 of 36`) and `scratchpad/audit/p6_lists.jl` section M (solver table, prints `live` for all 10).

---

### LEAD U4-18 [Low, confidence med, CROSS-FILE SEAM] src/contracts/Contracts.jl:313 → src/tasks/strongstrong/interface.jl
Claim: two of the checks `validate_configuration_metadata()` gained in the U3-4 repair, and which `PublicConfigurationEffectivenessContract` calls as its first act, cannot fail — the BPMObserver schema↔report comparison is guaranteed by construction, and `StrongStrongTask`'s default check compares the schema against a second hand-written literal instead of the constructor.
Mechanism: (i) `configuration_report(::BPMObserver)` (BPMObserver.jl:308-324) builds its entries by iterating `_BPM_OBSERVER_OPTION_SCHEMA` and naming each entry `field`, so `Set(entry.name) == Set(keys(schema))` is an identity; the validator's `schema_names == report_names` check is real for the five observers whose reports are hand-written tuples (BeamObservers.jl:831-880) and vacuous for the one observer the U3-4 fix added. (ii) The `StrongStrongTask` block compares `strong_strong_task_option_schema()` defaults against the literal `task_defaults = (luminosity_path=nothing, luminosity_append=false)` — a *third* copy of the same knowledge — where every neighbouring block reads the real constructor (`solver_configuration(GaussianPoissonSolver())`, `LongitudinalSlicing()`, `EveryNSteps()`, `StrongStrongDiagnostics()`). Changing the `StrongStrongTask` constructor default alone would leave both the schema and the literal stale and the check green. Noted and stopped: the fix lives in interface.jl, outside my region.
Repro:
```
julia --startup-file=no --project=. -e '
using Octopus; O=Octopus; b = O.BPMObserver()
println(Set(keys(O.observer_option_schema(b))) == Set(e.name for e in O.configuration_report(b)))'
```
prints `true` for any possible schema, because `configuration_report` derives the names from that schema; and `grep -n "task_defaults = " src/tasks/strongstrong/interface.jl` shows the hand-written literal.

---

## 3. Hardcoded-vs-derived enumeration diffs, in full

Every hardcoded list, tuple, dict or enumeration in `Contracts.jl`, with the
authoritative set derived from the registry / schemas / `subtypes`, and the diff.

| # | Hardcoded thing (line) | Authoritative source | Diff |
|---|---|---|---|
| 1 | `_symplecticity_contract_cases()` — 12 cases (:1172-1243) | `{kind : SymplecticityContract ∈ element_meta(kind).contracts}` = **`[:solenoid]`** | derived ⊄ hardcoded: **0 missing**. But against the structural set `{kind : Symplectic6DMap ∈ meta.tracking_methods}` (22 kinds) the hardcoded list is **missing 15**: `drift, hkicker, kicker, marker, multipole, octupole, quadrupole, sbend, sextupole, thin_dipole, thin_multipole, thin_quadrupole, thin_rf_cavity, thin_sextupole, vkicker`. See U4-8. |
| 2 | `_solver_contract_types()` — 4 solvers (:2338-2339) | `_subtypes_recursive(AbstractPoissonSolver)`, concrete, Octopus-defined = `{GaussianPICPoissonSolver, GaussianPoissonSolver, PICPoissonSolver, SpectralPoissonSolver}` | **0 missing today.** But the tripwire at :2464-2471 guards `contract.probes`, not this tuple — see U4-7. `subtypes` here is also non-recursive where `Registry.jl` uses `_subtypes_recursive`; today `subtypes == recursive` (empty difference measured), so no drift yet. |
| 3 | `_default_solver_option_probes()` — 4 keys (:2152-2166) | same as #2 | **0 missing** (this is the set the tripwire actually guards). |
| 4 | `_default_solver_option_alternatives()` (:2213-2250) + `_pic_family_alternatives()` (:2178-2211) | `keys(solver_option_schema(T))` per solver | **0 missing** — enforced per-option at :2504-2507 ("no declared alternative and no stated reason" ⇒ fail), pinned by `runtests.jl:2066-2072`. Genuinely derived. |
| 5 | `DEFAULT_INACTIVE_SOLVER_OPTIONS` — 10 pairs (:2257-2288) | live `(nameof(T), option)` pairs | **0 stale**: all 10 are live pairs. No tripwire keeps it so — U4-17. |
| 6 | `_solver_option_is_execution` — `(:execution, :performance)` (:2341) + the docstring's `(:physics, :numerical, :physics_override, :accuracy_performance, :diagnostic)` (:2301-2304) | categories in use across the four schemas = `[:accuracy_performance, :diagnostic, :execution, :numerical, :performance, :physics, :physics_override]` | **0 unclassified.** Note the shape: a new category falls silently into the "must move the observable" branch rather than failing. |
| 7 | `DEFAULT_ELEMENT_PARAM_PROBES` — 25 kinds (:1932-1986) | `registered_element_specs()` with a friendly constructor | **0 kinds without a probe** (the `example_spec` fallback at :2094-2096 covers the rest); **0 stale probe entries**. Structurally clean; the *content* of the `:sbend` probe is not — U4-4. |
| 8 | `DEFAULT_INACTIVE_ELEMENT_PARAMS` — 36 pairs (:1987-2037) | `(kind, key)` pairs actually consulted in the sweep | **0 stale**: all 36 matched a live pair. No tripwire — U4-17. |
| 9 | `_ptc_reference_specs()` — 55 cases (:1635-1817) | rows of `validation/reference/ptc_madx_5.03.06.tsv` | **0 missing, both directions covered in the direction that matters**: the guard at :1876-1880 fails naming any declared spec the table has no rows for, pinned by a truncated-table must-fail test (`runtests.jl:1923-1938`). The generator consumes `_ptc_reference_specs()` (verified: `occursin("_ptc_reference_specs", generate_ptc_reference.jl) == true`), so the table cannot drift from the spec list without the guard firing. Live: 55 of 55 compared, worst deviation 5.0e-13. **Clean.** |
| 10 | `_PTC_DEFAULT_ATOL` — empty (:1819) | — | Empty and honestly documented as such since U3-9. Clean. |
| 11 | `(:CIC, :TSC)` deposit-method guard (:790-794) | values `PICPoissonSolver` accepts | **exact match**: `:CIC`/`:TSC` accepted, `:NGP`/`:typo` rejected by the solver. A hand copy, but it fails loudly (returns a failed `ContractResult`) rather than silently narrowing. Clean-with-a-note. |
| 12 | `contract_paths` — 5 knob paths (:202-206) | `__knob_contract__.*` names appearing in the same function body | **exact match** (`brho, current, k1, transfer, unset` both sides). Hand mirror inside one function; clean today. |
| 13 | `required_families = Set(_CUDA_PIC_LAUNCH_FAMILIES)` (:593) | the same constant the emitting code uses | Derived, not duplicated. Clean. Live: all 7 families observed (`deposition, field, gather_scatter, green, kick, luminosity, spectral`). |
| 14 | `description` methods — 9 (:185-198, :1146, :1330, :1497, :2335) | `_subtypes_recursive(AbstractContract)`, concrete = 11 | **missing 2**: `PTCConsistencyContract`, `ElementParameterEffectivenessContract` — U4-14. |
| 15 | `cuda_threads_sweep = (64,128,256,512)` (:484) | — | A deliberate sweep, not a mirror of anything. Clean. |
| 16 | export list (:1-12) | concrete `AbstractContract` subtypes | **exact match**: all 11 exported, no extras. Clean. |

---

## 4. Contract-to-runner table

All 11 concrete contracts, every runner, and what the runner asserts. **U3-6 is
closed** — no contract traces to no runner. Two partial gaps remain (rightmost
column).

| Contract | `test/runtests.jl` | `validation/` | What the suite asserts | Gap |
|---|---|---|---|---|
| `ElementTrackingBackendConsistencyContract` | 4247, 4252, 4270 | `tracking_backend_consistency.jl`, `lattice_cells.jl` | `passed(r)` for CPU/CPU; `status ∈ (:passed,:skipped)` for CPU/CUDA | — |
| `StrongStrongGaussianBackendConsistencyContract` | 3787 (under `CUDA_TESTS_ACTIVE`) | `strong_strong_gaussian_backend_consistency.jl` + 3 others | `.passed` | CUDA-gated; `@test_skip` otherwise |
| `StrongStrongPICBackendConsistencyContract` | 3786 (under `CUDA_TESTS_ACTIVE`) | `strong_strong_pic_cache_backend_consistency.jl` | `.passed` | default config only; `green_cache=:none` / `batch_mode=:sequential` legs unrun and vacuous (U4-9) |
| `PublicConfigurationEffectivenessContract` | 3781 | `public_configuration_effectiveness.jl` | `status === :passed \|\| (:skipped && !CUDA_TESTS_ACTIVE)` | worker-invariance leg silently empty at `-t1` (U4-10) |
| `KnobEffectivenessContract` | 8072 | — | `.passed` + metric pins | — |
| `SymplecticityContract` | 3739, 3751 (must-fail control), 3759, 8174 | `symplecticity_validation.jl`, `tracking_backend_consistency.jl` | `.passed`, `kinds_declaring_without_case == 0`, `Solenoid_residual` present, `GaussianStrongBeam_residual <= 5e-7`, plus a registered-liar must-fail | tripwire has 1 degree of freedom (U4-8) |
| `HighEnergyWeakStrongLimitContract` | 8178 | `high_energy_weakstrong_limit.jl` (mirrors, does not call) | `.passed` + `gaussian_proton_max_abs_error <= 2e-14`, `pic_luminosity_relative_error <= 0.08` | sharp half is kernel-circular (U4-11) |
| `PTCConsistencyContract` | 1914 (`=== :passed`), 1932 (must-fail), 4147 (`∈ (:passed,:skipped)`) | `generate_ptc_reference.jl`, `lattice_cells.jl` | `cases == length(_ptc_reference_specs())`, per-case `dev_*` metrics, truncated-table must-fail | — |
| `ElementParameterEffectivenessContract` | 1886, 1904 (must-fail control), 3765 (broken-baseline control) | — | `:passed`, `ignored == 0`, `checked > 200`, `skipped_kinds == 0`, `broken_kinds == 0`, plus `drift.nst` must-fail and a `quadrupole` broken-baseline must-fail | pins cannot see the 112 silently uncounted parameters (U4-2) |
| `CoherentModePhysicsContract` | 8188 (`:pic`), 8190 (`:gaussian`, must-fail) | `coherent_beam_beam_modes.jl` (parallel implementation, not the contract) | `:pic` passes, `:gaussian` fails with `lambda` ordering and sigma-drift pins | **`:gaussian_pic` branch has no runner** (U4-15) |
| `SolverOptionEffectivenessContract` | 2060, 2068 (must-fail), 2078 (must-fail), 3775 (probe-less-solver control) | — | `status ∈ (:passed,:skipped)`, `cpu_options_checked > 60`, "no declared alternative" must-fail, "equal to its own probe value" must-fail, probe-less-solver must-fail | tripwire guards the wrong set (U4-7) |

CI (`.github/workflows/ci.yml`) runs `Pkg.test` only; `test/nightly_suite.sh`
is the opt-in GPU gate. Every CUDA-dependent leg above is `@test_skip`ped
visibly on a CPU-only runner, which is what AGENTS.md requires.

---

## 5. Clean list — audited sound, with the evidence

Each entry states what was compared or measured, not merely that no complaint
was found.

1. **`ContractResult` skip honesty, all 8 skip sites.** `ContractResult(status::Symbol, …)` at :35-39 sets `passed = (status == :passed)`, so `:skipped` is never `passed`. Verified at :479-481 (PublicConfiguration, after the CPU half), :642-645 (ElementTracking), :686-689 (Gaussian), :782-785 (PIC), :1839-1841 (PTC, no table), :2573-2576 (SolverOption). The SolverOption path at :2570-2572 reports accumulated failures **before** skipping, so a CPU failure is never hidden behind a missing GPU.
2. **RNG discipline — U3-1 closed, verified live.** All six RNG-touching contracts save/restore in `try/finally`: ElementTracking :654-665, Gaussian :695-776, PIC :800-927, HighEnergyWeakStrongLimit :1379-1447 (new), CoherentMode :1580-1602 (new), SolverOption :2472-2478. Measured with a `0xDEADBEEF` sentinel around all 12 live contract runs: **zero leaks**.
3. **PTC contract.** 55 of 55 declared specs compared against the committed MAD-X 5.03.06 table, worst deviation **5.0e-13** against `default_atol = 1e-11`. Bidirectional coverage guard at :1876-1880 with a truncated-table must-fail pin. `_ptc_reference_path` resolves via `@__DIR__` and now sorts by numeric version fields (`natkey`, :1832) — correct for the "5.10 vs 5.09" case the U21-7 fix names, though only one table exists today.
4. **`_contract_coordinate_metrics` (:978-1021).** Criterion is `max_allowed_ratio <= 1` where `allowed = atol + rtol*scale`; the pointwise ratio and `max_component_rel_scale` are carried as diagnostics with the reasoning stated at :1001-1005. With `atol = rtol = 0` (the exactness comparisons at :344 and :241) the criterion degenerates to `diff <= eps()`, i.e. bitwise — which is what those call sites want.
5. **`_contract_backends_available` (:930-948).** `CUDA.functional(false)` inside a `try`, honest reason strings, `CPUThreadsBackend` short-circuited, unsupported backends named. No path returns `true` without a device.
6. **`SolverOptionEffectivenessContract`'s option-level completeness.** An option with neither an alternative nor a stated reason **fails** (:2504-2507); an alternative equal to the probe's own value **fails** (:2516-2520); both pinned by must-fail injections at `runtests.jl:2066-2081`. Measured live with CUDA: 68 CPU options, 10 CUDA-only options all checked, 2 launch surfaces, 10 documented exemptions, 0 stale exemptions.
7. **The launch-surface check's non-circularity (:2659-2665).** The comment states the rule and the code follows it: `haskey(solver_option_schema(T), :backend_configurations)` decides what to test, never `_pic_launch_solver`. Asking the installer would make the check circular in exactly the way the contract exists to catch. Verified live — both PIC-family solvers emit `:cuda_pic_launch` receipts with `threads == 64` for all seven families.
8. **CUDA noise-floor calibration (:2600-2620).** Baseline run twice, spread × 100, floored at 1e-10, with the rationale (float atomic reordering vs a genuine algorithmic difference, seven orders apart) recorded inline. Live run: all 10 CUDA-only options within the floor.
9. **The two-collision `TrackingContext` observable (:2354-2381).** `luminosity_schedule` needs a context and the slice-pair Green cache needs a second collision; running two turns through `with_turn` is the fix that made those options observable rather than "ignored". The docstring records that the probe was fixed rather than the code.
10. **`ElementParameterEffectivenessContract`'s broken-baseline handling (:2102-2111, :2132-2134).** U3-7 closed: a throwing baseline is now a reported failure naming the kind, with a `:broken_kinds` metric and a must-fail pin at `runtests.jl:3762-3768`. Measured: `skipped_kinds = 0`, `broken_kinds = 0`, 0 kinds without a probe.
11. **`PublicConfigurationEffectivenessContract`'s pre-mutation rejection checks.** Four of them (:440-447 solver mismatch, :530-534 CUDA device mismatch, :555-563 invalid inherited PIC launch, plus the new equal-configuration acceptance complement at :449-474) assert both that the throw happened **and** that the coordinates are unchanged. The new complement at :449-474 is the right shape: it pins that rejection keys on configuration, not on `objectid`, so the pair of checks is falsifiable in both directions.
12. **`KnobEffectivenessContract` cleanup and criteria.** `_forget_knob!` for all five paths in `finally` (:303-307); the five knob paths mentioned in the body exactly match the cleanup tuple (measured); pass criteria are exact zeros against a directly-parameterized reference, not tolerances.
13. **`_coherent_fractional_tune` (:1500-1511).** Hann window, `rfft`, interior-only `argmax` (`2:length(a)-1`, so `a[k±1]` is always in bounds), parabolic interpolation with a zero-denominator guard. The unknown-solver branch at :1546-1549 **throws** rather than silently defaulting — the one place in this file where an unknown symbolic option is refused.
14. **`_symplectic_form6` / `_contract_fd_jacobian6` (:1149-1170).** Standard `S`, central differences with `h = step·max(|q|,1)`; the docstring's step-squared scaling claim (7.9e-10 at 3e-8 through 7.9e-4 at 3e-5) is consistent with the truncation-error argument, and the `default_tolerance` floor now sits at 5.0e-8 == the tightest per-case tolerance, so every declared case tolerance binds (U3-2's fix, verified in the source).
15. **Contract structs reject unknown keywords.** All 11 are `Base.@kwdef`; `SymplecticityContract(nonsense=1)` raises `MethodError` (measured). The permissiveness is only at the `validate` entry point (U4-13).
16. **Export/type-tree agreement.** All 11 concrete `AbstractContract` subtypes are exported and all are defined in `Octopus`; the export list at :1-12 has no extras and no omissions (measured against `_subtypes_recursive(AbstractContract)`).

---

## 6. Not checked, and why

- **`ext/` CUDA extension internals and the CUDA kernels themselves.** Outside the region; the contracts were exercised against a real device instead (`CUDA.functional() == true`, RTX 4500 Ada).
- **Whether the physics claims the contracts encode are right** (the Yokoya band 1.12–1.30, the 8% PIC tolerances, the Vlasov reference values). Phase-7 obligation of the physics units, not of a reader of the contract file; I verified only that the declared tolerances *bind* and that the comparisons reach them.
- **`validate_element_metadata` (Knowledge.jl:920-930)** — the circular element-metadata validator named in the brief. It is the source of `meta.contracts`, which U4-8's tripwire consumes, so I read it and noted the seam; auditing it belongs to the Knowledge/registry unit.
- **The deferred-validation design for element-spec *values*** (U4-12 secondary). `misalign_convention=:MADX` is accepted and stored until a misalignment wrap is compiled. That is the element layer's documented pattern (`QuadrupoleSpec(L="not a length")` behaves the same way), so judging it is the elements unit's call, not mine. I measured it and stopped.
- **A first-pass per-kind acceptance table for `misalign_convention` was a probe artifact and is withdrawn.** An intermediate probe appeared to show that six kinds accepted arbitrary symbols while three rejected them; the real variable was whether the kind's *probe* carried a placement offset, not the kind. Recorded here so the wrong table is not re-derived from the scratch scripts.
- **The `luminosity_append` / `MomentObserver(append=…)` effectiveness question** raised as U3-5. `strong_strong_task_option_schema()` now exists and `validate_configuration_metadata` checks it, so the schema gap is closed; the residual defect there is the hand-written `task_defaults` literal (U4-18). I did not re-derive the whole post-contract public-option surface — that is an interface.jl question.
- **The full CI-settings suite gate** (`--threads=4 Pkg.test`). Not run: this is a read-only audit unit and the gate takes ~40 min; I ran every contract in the region individually at `-t4` with CUDA instead, which is the coverage this region needs. A fix session must still finish through the full gate (Measured Lesson 9).
- **`_solver_contract_spread`'s `zip` truncation (:2388-2398).** `zip` silently stops at the shorter sequence, so unequal coordinate or luminosity vectors would compare a prefix. I could not construct a case where the lengths differ on the CUDA half (both sides are `turns=1`, so one luminosity row each, and the coordinate vectors are fixed at 12·n), so this stays an unexercised structural note rather than a lead.
