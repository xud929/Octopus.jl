# U3 Audit Report — src/contracts/Contracts.jl (commit 6a3f39a)

## Coverage statement

- `src/contracts/Contracts.jl`: **lines 1–2544 read in full** (every line, four Read passes: 1–400, 400–850, 850–1300, 1300–1750, 1750–2200, 2200–2544).
- Collaborators read for verification: `src/tasks/strongstrong/interface.jl` 1440–1790 (`validate_configuration_metadata`, task `configuration_report`, `_CUDA_PIC_LAUNCH_FAMILIES`), `src/tasks/strongstrong/gaussian_pic.jl` 60–180, `src/tasks/BeamObservers.jl` 640–760, `src/knowledge/Knowledge.jl` 320–360, `src/elements/solenoid.jl` 410–430, `test/runtests.jl` (grep + excerpts 1790–1995, 3195–3262, 3595–3640, 7060–7110), `.github/workflows/ci.yml`, `validation/*.jl` tails.
- Probes (all run, CPU host that turned out to have a functional CUDA device; the effectiveness-metrics probe therefore exercised the CUDA halves too):
  - `U3/probe_rng_leak.jl` — confirmed RNG-state leak.
  - `U3/probe_static_gaps.jl` — confirmed docstring drift, solenoid gap, validator enumeration staleness, append coverage gap.
  - `U3/probe_param_baseline_skip.jl` + `probe_param_baseline_skip2.jl` — confirmed silent-skip of a broken kind and silent acceptance of unknown element keywords.
  - `U3/probe_effectiveness_metrics.jl` — live SolverOption + PublicConfiguration runs: both **:passed** incl. CUDA halves; "68 on CPU, 10 CUDA-only options, 2 launch surfaces".

## Leads

### U3-1 — Contracts.jl:1310 and :1439 — HighEnergyWeakStrongLimitContract and CoherentModePhysicsContract clobber the global RNG state and never restore it — MEDIUM
Violated invariant: the file's own convention (ElementTracking 621–631, Gaussian 662/742, PIC 767/893, SolverOption 2300–2307 all save/restore in try/finally; 2315–2319 records "a contract whose result depends on its caller is not a contract" — these two contracts are themselves the seed-movers that create that hazard for whoever runs after them). `validate(HighEnergyWeakStrongLimitContract())` leaves seed `0x0123456789abcdef` behind; `validate(CoherentModePhysicsContract(...))` leaves `20260727` (`0x1352777`). Both run mid-suite in runtests 7086/7096, so every later testset inherits a moved seed — the exact mechanism of the recorded SolverOption defect.
Repro: `probe_rng_leak.jl` — sentinel `0xDEADBEEF` before, contract seed after, LEAKED=true for both.

### U3-2 — Contracts.jl:1081 vs :1109 — SymplecticityContract docstring signature advertises `default_tolerance=5.0e-7`; the struct default is `5.0e-8` — LOW (docstring↔code drift)
The tolerance fix described in the comment at 1106–1109 (part 2/S3 class: floor must sit at the tightest per-case tolerance or the four 5.0e-8 cases never bind) was applied to the code but not to the docstring's signature line. The fix itself is correct: floor 5.0e-8 == tightest case, all per-case tolerances now bind.
Repro: `probe_static_gaps.jl` (doc says 5.0e-7: true; struct default = 5.0e-8).

### U3-3 — src/elements/solenoid.jl:421 + Contracts.jl:1139–1200 — solenoid declares `SymplecticityContract` in its element metadata, but `_symplecticity_contract_cases()` contains no solenoid case; nothing ties `contracts=[...]` declarations to the contract's hand-enumerated case list — MEDIUM
`required_contracts(ElementSpec{:solenoid})` (user-facing via construction help) claims SymplecticityContract coverage the contract does not provide. Case list: [:Linear6D, :CrabDispersion, :MomentumDispersion, :XYCoupling, :ThinCrabCavity, :ChromaticityKick, :ThinStrongBeam, :ThinStrongBeamChromatic, :ThinStrongBeamExact, :GaussianStrongBeam]. `validate_element_metadata` checks a declared contract *is an AbstractContract* (runtests 3259), not that the contract exercises the declarer. Same hardcoded-enumeration class as defect 2: a new Symplectic6DMap element is invisible to the contract until hand-added.
Repro: `probe_static_gaps.jl` (declares: true; solenoid case present: false).

### U3-4 — interface.jl:1542–1664 (called from Contracts.jl:313) — `validate_configuration_metadata` hardcoded enumerations are stale TODAY — MEDIUM (inherited open item; exact blast radius)
Hand-enumerated and missing right now:
- **GaussianPICPoissonSolver absent** (validator checks PIC :1582, Gaussian :1596, Spectral :1607 for schema↔fieldnames, defaults↔constructor, consumer-named — none of these run for GaussianPIC; its 3 extra options `margin_sigma`, `neutralize`, `coupling_tol` are never default- or consumer-checked by the validator; risk reduced because its schema is a mechanical `merge` of the PIC schema, gaussian_pic.jl:129).
- **BPMObserver absent** from the observer lists at :1642–1650 despite having an `observer_option_schema` (BPMObserver.jl:305).
- **Observers get no default-vs-constructor check at all** (solvers/slicing/schedules do); the observer check (schema keys == report keys, :1656–1660) compares two hand-maintained lists with no fieldname anchor — a new public observer field forgotten in both stays invisible.
- **No task-level schema exists**: StrongStrongTask's `luminosity_path`/`luminosity_append` appear only in a hand-built `configuration_report` (interface.jl:1765–1778) that no validator cross-checks.
- Second copy of the solver enumeration: Contracts.jl:2188 `_solver_contract_types()` hand-lists the same 4 solvers for SolverOptionEffectivenessContract — a 5th solver is silently outside both.
Tripwire shape: derive the checked set from an architectural root — e.g. fail when any type owning a specialized `solver_option_schema`/`observer_option_schema` method (reflection over `methods(...)`) is not in the validated set — instead of two independent hand lists.
Repro: `probe_static_gaps.jl` (validator body mentions GaussianPICPoissonSolver: false; BPMObserver: false; StrongStrongTask/luminosity_append: false/false; observer default check: false).

### U3-5 — Contracts.jl:377 and :2188/2331 — `MomentObserver(append=...)` and `StrongStrongTask(luminosity_append=...)` are the first post-contract public options outside every effectiveness contract — LOW-MEDIUM
Mechanism, shown mechanically: the only schema-swept effectiveness contract is SolverOptionEffectivenessContract, whose domain is `union(keys(solver_option_schema(T)) for T in _solver_contract_types())` = 42 distinct names; `:append` and `:luminosity_append` are not in it. PublicConfigurationEffectivenessContract is a hand-enumerated script: it builds MomentObserver **without** `append` (Contracts.jl:377) and never sets `luminosity_path`. `Contracts.jl` contains zero references to either option (the single "append" match is Base `append!` at :2272). Mitigations: `append` IS registered in `observer_option_schema(MomentObserver)` (consumer + schema↔report checks apply); both options have direct behavior tests (runtests 3273–3327 for luminosity_append, 3330–3380 for append). `luminosity_append` has no schema at all (see U3-4). So: not untested behavior, but a demonstrated fall-through of the *effectiveness-contract* layer, and the fall-through mechanism (hand-enumeration boundary) is structural.
Repro: `probe_static_gaps.jl`.

### U3-6 — Contracts.jl:310, :650, :746 — three contracts are never executed by the test suite or CI — MEDIUM (defect class 6)
`PublicConfigurationEffectivenessContract`, `StrongStrongGaussianBackendConsistencyContract`, `StrongStrongPICBackendConsistencyContract` appear nowhere in `test/runtests.jl`; `.github/workflows/ci.yml` runs `Pkg.test` only. Their only runners are manual scripts (`validation/public_configuration_effectiveness.jl`, `validation/strong_strong_gaussian_backend_consistency.jl`, `validation/strong_strong_pic_cache_backend_consistency.jl`). PublicConfiguration's CPU half (worker receipts, invalid-thread/typo rejection, observer schedule+capacity receipts, report inherited/inactive, solver-mismatch pre-mutation rejection) is CI-runnable and currently unrun in CI. Live probe run confirms all three implementations work today (PublicConfiguration :passed incl. CUDA on this host).
Repro: `grep -c` on runtests (0 hits) + `probe_effectiveness_metrics.jl`.

### U3-7 — Contracts.jl:1960–1964 — ElementParameterEffectivenessContract silently skips a kind whose baseline construction/compile throws — MEDIUM-LOW (sibling of the recorded "skip a broken solver" defect)
`baseline = try ... catch err push!(skipped, meta.kind); continue end`: a broken element passes the contract with `skipped_kinds` merely incremented. Probe: default run gives checked=238, ignored=0, skipped_kinds=3, :passed; with a quadrupole probe whose baseline throws (`L="not a length"`), checked drops to 222, skipped_kinds=4, status **:passed**. Mitigation: runtests (~1802) pins `skipped_kinds <= 3` with exactly zero headroom today, so a regression in a currently-probed kind WOULD trip the suite — but through a pin whose stated meaning is "kinds without a probe", and the contract itself misreports. Also note :1939 `meta === nothing && continue`: a registered spec without ElementMeta is not even counted as skipped.
Repro: `probe_param_baseline_skip2.jl`.

### U3-8 — Contracts.jl:2295 — `_solver_contract_receipt_carries` is vacuous for consumer `:cuda_pic_launch` — LOW (CUDA-only)
`consumer === :cuda_pic_launch && haskey(r.values, :threads) && return true` accepts ANY launch receipt regardless of option identity or requested value, so the per-option claim at 2417–2419 ("the value must appear in a receipt named by the option's declared consumer") degrades to receipt-existence for that consumer. Mitigated by the dedicated launch-surface check (2494–2531) which does verify `threads == requested` for all 7 families on both launch surfaces (live run: families [:deposition, :field, :gather_scatter, :green, :kick, :luminosity, :spectral], all effective).

### U3-9 — Contracts.jl:1734 + docstring 1538–1541 — `_PTC_DEFAULT_ATOL` is permanently empty while the docstring says "see ... the per-case defaults below" — LOW (docstring↔code drift / dead structure)
Every case in fact uses `default_atol=1e-11`; the per-case default table the docstring points at has no entries.

### U3-10 — via Contracts.jl:1933–1990 (root cause in elements/registry, cross-file) — element friendly constructors accept unknown keywords and wrong-typed values silently, end-to-end — MEDIUM (hand to the elements auditor)
`QuadrupoleSpec(L=0.4, k1=1.7, this_keyword_does_not_exist=1.0)` constructs, compiles, and tracks without any error (probe (a): no throw; the contract ran it through baseline+238 checks). `QuadrupoleSpec(L="not a length")` also constructs (validation deferred to compile). Contrast: `Beam` rejects unknown keywords, and PublicConfigurationEffectivenessContract asserts exactly that (Contracts.jl:366–374, "unknown Beam keyword was silently ignored"). ElementParameterEffectivenessContract iterates `parameter_schema(T)` only (:1966), so it structurally cannot see an undeclared stored keyword — the docstring's claim of closing the "silently ignored non-default request" gap (:1826–1828) does not cover the misspelled-keyword variant of that same failure mode.
Repro: `probe_param_baseline_skip2.jl` part (a).

## Inventory — every contract in the file

| Contract (def line) | Claims to prove | Implementation proves it? | Runner | Pinning test | Verdict |
|---|---|---|---|---|---|
| `ContractResult`/`passed`/fallback `validate` (23–183) | result carrier; `:skipped` ⇒ `passed=false` | yes — both constructors consistent | — | used everywhere | sound |
| `ElementTrackingBackendConsistencyContract` (63) | same line, two backends, identical coordinates; RNG snapshot per run | yes; saves/restores RNG; skip honest (609) | runtests 3608/3613; validation/tracking_backend_consistency.jl | runtests 3608 (CPU/CPU must pass; CPU/CUDA pass-or-skip) | sound |
| `StrongStrongGaussianBackendConsistencyContract` (88) | CPU/CUDA soft-Gaussian coords + full luminosity series agree | yes; RNG restored; skip honest; tolerances bind via `max_allowed_ratio<=1` | validation script only | **none in suite/CI** | sound impl; U3-6 |
| `StrongStrongPICBackendConsistencyContract` (120) | CPU/CUDA PIC coords, luminosity, per-pair series, cache history identical w/ ≥1 reuse | yes; guards (turns≥2 for slice_pair, deposit enums); skip honest | validation scripts only | **none in suite/CI** | sound impl; U3-6 |
| `PublicConfigurationEffectivenessContract` (150) | public config reaches runtime consumers (CPU workers, CUDA fused launch, PIC launch families, pre-mutation rejections, observer schedule/capacity) | yes — receipt-based, all asserted via effective flags; CUDA-unavailable ⇒ honest `:skipped` after CPU half | validation script only | **none in suite/CI** | sound impl; U3-6; hand-enumerated boundary (U3-5) |
| `KnobEffectivenessContract` (170) | knob expressions reach compiled runtime; epoch invalidation; guards fire; receipt emitted | yes — exact-zero comparisons vs direct-parameter reference; cleans namespace in finally | runtests 7073 | runtests 7073–7075 | sound |
| `SymplecticityContract` (1102) | FD symplecticity of 10 runtime maps; Lorentz pair quasi-symplectic | yes — `norm(J'SJ−S)≤tol`, floor now 5.0e-8 so all case tolerances bind | runtests 7082 | runtests 7082–7084 | sound math; U3-2 docstring, U3-3 solenoid gap, RNG-free |
| `HighEnergyWeakStrongLimitContract` (1254) | strong-strong → frozen-source weak-strong at E→∞ (Gaussian exact, PIC toleranced) | yes — independent hand-rolled reference kick | runtests 7086 | runtests 7086–7089 | sound physics; **U3-1 RNG leak** |
| `CoherentModePhysicsContract` (1410) | Yokoya Λ in Vlasov band per solver; σ-mode unshifted; moment closure must fail | yes — FFT tune extraction; must-fail asserted for :gaussian | runtests 7096 | runtests 7096–7102 (pass AND must-fail) | sound; **U3-1 RNG leak** |
| `PTCConsistencyContract` (1543) | LatticeMagnet tracking matches committed PTC table, all 55 declared cases | yes — external committed reference; bidirectional coverage guard (1787) | runtests 1817, 3508 | runtests 1817–1840 (incl. truncated-table must-fail) | sound; U3-9 minor |
| `ElementParameterEffectivenessContract` (1911) | every declared element parameter reaches the compiled map | mostly — 238 params checked, 0 ignored; but broken kind ⇒ silent skip | runtests 1795 | runtests 1795–1814 (`skipped_kinds<=3`, zero headroom) | **U3-7**, U3-10 boundary |
| `SolverOptionEffectivenessContract` (2176) | every declared solver option reaches a consumer (68 CPU; 10 CUDA-only; 2 launch surfaces; 10 exempted with reasons) | yes — schema-driven (circularity fix verified at 2488–2494), RNG pinned+restored, no-alternative ⇒ fail, probe-equal-alternative ⇒ fail, noise-floor-calibrated CUDA half; live run :passed incl. CUDA | runtests 1963 | runtests 1963–1988 (incl. two must-fail injections) | sound; U3-8 (minor, CUDA receipt check), U3-4 (hand-listed solver tuple) |

Counts today (live): CPU options checked = 68; CUDA-only options = 10 (all 10 checked on this host); launch surfaces = 2; exemptions in `DEFAULT_INACTIVE_SOLVER_OPTIONS` = 10 pairs; distinct option names in sweep domain = 42. (Assignment's "13 CUDA-deferred, 7 exempted" are stale relative to 6a3f39a.)

## Defect-class dispositions (this file's history)

1. **Circular validation**: SolverOption's decide-from-schema fix verified real (2488–2494; schema is the declaration root in interface.jl/gaussian_pic.jl; `_CUDA_PIC_LAUNCH_FAMILIES` is shared with the emitting code, not duplicated). No remaining circular check found in Contracts.jl. Nearest sibling shape: the observer schema↔report comparison inside `validate_configuration_metadata` (two mirrors, no field anchor — U3-4).
2. **Hardcoded enumerations**: characterized in U3-4 (+U3-3 case list, +`_solver_contract_types`). Stale today: GaussianPIC, BPMObserver, task-level options, solenoid symplecticity case.
3. **Post-contract options**: U3-5 — both fall outside the effectiveness layer; `append` schema-registered, `luminosity_append` schema-less; both directly unit-tested.
4. **Tolerances that never bind**: Symplecticity floor fixed (5.0e-8, binds); all other declared tolerances (atol/rtol/luminosity_rtol/gaussian_atol/pic_*/default_atol/contract.atol) verified reached by their comparisons. Skip honesty verified at all 6 skip sites (`:skipped` ⇒ `passed=false`; SolverOption reports failures before skipping; PublicConfiguration never reports an unrun CUDA check as passed).
5. **Skip-broken / caller-RNG**: SolverOption fixed on both counts (verified). Siblings found: U3-7 (ElementParameter baseline skip); U3-1 (the two physics contracts move the caller's RNG — the mirrored obligation).
6. **Never executed**: U3-6 (three contracts, validation-scripts only).
7. **Nothing-interpolation / docstring drift**: no `$(nothing)` interpolation found (the `luminosity_deposit_method` branch can't fire on `nothing`); drift found at U3-2 and U3-9.

## Sound (verified, no lead)

- `_contract_coordinate_metrics` (945–988): tolerance criterion `max_allowed_ratio<=1` with honest diagnostic/criterion separation and `max_component_rel_scale` context.
- `_contract_backends_available` (897–915): CUDA availability via `CUDA.functional(false)` with honest reason strings.
- PTC bidirectional coverage guard (1787–1791) + its must-fail pinning test.
- Two-collision `TrackingContext` observable (2204–2231): fixes the schedule/cache-never-bind probe defect, documented.
- CUDA noise-floor calibration (2436–2454): repeat-spread × 100 floored at 1e-10, rationale recorded.
- SolverOption no-alternative ⇒ fail and alternative==probe ⇒ fail, both pinned by injection tests.
- Knob contract cleanup in `finally` (303–307); exact-zero pass criteria.
- RNG save/restore in all four backend/solver contracts (621, 662, 767, 2300).
- PublicConfiguration pre-mutation rejection checks assert coordinates unchanged, not just the throw (434–441, 497, 522–525).
- `_ptc_reference_path` resolves via `@__DIR__` (works under include or package load), latest table by name sort.
