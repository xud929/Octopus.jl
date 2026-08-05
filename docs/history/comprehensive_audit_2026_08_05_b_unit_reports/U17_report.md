# U17 (this session) audit report — test/runtests.jl lines 1–2200

Repo: /cfs/ad/dxu/Library/Julia/Octopus @ HEAD `7de4d81`. Julia 1.12.4, CUDA device
present and functional on this box.

**ID collision, read this first.** `docs/history/comprehensive_audit_2026_08_05_unit_reports/U17_report.md`
already exists and owns the IDs `U17-1 … U17-8` (region: lines 3800–7766); the current
`test/runtests.jl` header comment at line 32 cites `U17-7` from it. To keep leads
greppable I number this unit's leads **`U17b-1 … U17b-8`**. Rename at will, but do not
merge the two numbering spaces.

## Provenance

- **Read**: every line of `test/runtests.jl` 1–2217 (the last testset opening inside the
  assigned region, "Element parameters carry their own number type", opens at 2084 and
  closes at 2217; the next testset opens at 2219 and is outside). Also read:
  `git diff 6a3f39ab HEAD -- test/runtests.jl` in full (the four hunks landing inside this
  region are at new lines 12–39, 1516–1525, 1583–1658, 1889–1910, 2187–2213);
  `AGENTS.md` "Hard-Won Rules"; `docs/comprehensive_audit.md` "Phase 9" and "Measured
  Lessons"; `U16_report.md` (the prior reading of this region, at 83e1d38);
  `src/elements/lattice_magnets.jl:35–120`, `src/elements/solenoid.jl:70–124`,
  `src/contracts/Contracts.jl:1836–1900, 2040–2140, 2560–2580`,
  `src/knowledge/Knowledge.jl:865–990`.
- **Executed** (all read-only; scripts in
  `/tmp/claude-320114/-cfs-ad-dxu/37c712a3-734a-4817-a05e-4c9e12cabcef/scratchpad/audit/`):
  - `region_1_2217.jl` — `head -2217 test/runtests.jl` run in isolation with
    `--threads=4`: **31/31 testsets pass, 1139 assertions, 0 fail, 0 error, 0 broken**
    (log: `region_run.log`). This is the "which testsets actually RAN" record for the
    region, including both CUDA-gated branches.
  - `probe_adsweep.jl` — exact contents of the AD sweep's verified/caught buckets.
  - `probe_contracts.jl` — the three contracts' status and metrics, plus the executed
    negative control.
  - `probe_series.jl` — **mutation controls**: pre-fix `_curv_vers`, pre-fix
    `_sol_log_over_h`, and the pre-fix closed-form `_wedge` re-implemented in scratch and
    run through the testset's own assertions.
  - `probe_headroom.jl` — measured value vs asserted bound for every load-bearing
    tolerance in the region, plus two injected-defect controls.
  - `probe_nearround.jl` — headroom for the 133 assertions of "Near-round Gaussian
    transition" and the round-Gaussian Hessian.
  - `probe_misc.jl` — non-vacuity of the chunked-radiation pin, Float32 soft-vs-weak
    deltas, `inverse_erf` circularity, `_wedge_quad` non-identity, contract check count.
  - `probe_abort.jl` — confirms Julia aborts the file at the first failing top-level
    testset (the second testset does not run).
- Environment: probes needing ForwardDiff run under a scratch project
  (`audit/env`) that `dev`s the repo and adds ForwardDiff; `Project.toml` keeps
  ForwardDiff in `[extras]`, so `--project=.` cannot load it.

## Verdict

The region is in good shape and materially stronger than at the previous reading: three
of U16's five leads (U16-1 tautology, U16-2 decorative negative control, U16-5 slack AD
floor) are repaired at HEAD, and the repairs are real — I re-measured each. The new,
never-audited code (the "Series helpers" testset, 1586–1658) carries **three executed
mutation controls that genuinely fail on the recorded pre-fix implementations**. What
remains is one fragile tolerance, a set of seam assertions with no discriminating power,
a few floors with slack, and five assertions that cannot fail.

---

## Leads

### LEAD U17b-1 [Medium, confidence high] test/runtests.jl:1599-1601
Claim: the `_curv_vers` seam loop asserts `< 1.0e-14` on a quantity whose measured value
is 5.9e-15 and whose error is entirely the sub-ulp rounding of `cos`; a one-ulp change in
`cos` (different Julia version, or a build where `muladd` does not lower to `fma`) makes
it 1.4e-14–2.05e-14 and turns the whole suite red from line 1600 onward.
Mechanism: on the closed branch `_curv_vers` computes `(1 - cos(u))/h`. At `u = 0.13`,
`1 - cos u = 8.447e-3`, so any error in `cos u` is amplified by `1/(1-cos u) = 118x`.
Half an ulp of `cos` (1.1e-16) is therefore 1.3e-14 of relative error — larger than the
entire bound. Measured today: relerr `5.89e-15` = 0.45 ulp of `cos`, i.e. 1.70x from the
bound. Recomputing the same expression with `cos` replaced by `prevfloat(cos u)` /
`nextfloat(cos u)` gives `7.15e-15` / `1.91e-14`. Same shape at `nextfloat(0.125)`
(5.65e-15; −1 ulp → 1.99e-14) and at `0.15` (4.09e-15; −1 ulp → 1.39e-14). Only
`prevfloat(0.125)` is safe, because there the fixed code takes the series branch.
Severity is set by the ordering caveat the file itself documents at lines 32–39 and by
`probe_abort.jl`: a failure here silently drops the ~7,150 later lines, including every
absolute-beam-beam backstop.
Repro: `julia --project=<env> probe_series.jl` / `probe_headroom.jl` section A. Or
directly: `relerr(x,r)=Float64(abs((big(x)-r)/r)); vr(h)=(1-cos(big(h)))/big(h);`
`relerr(Octopus._curv_vers(0.13,1.0), vr(0.13))` → `5.892314153631205e-15` against the
asserted `1.0e-14`; `relerr((1-nextfloat(cos(0.13)))/0.13, vr(0.13))` →
`1.9148246936442173e-14`.

### LEAD U17b-2 [Low, confidence high] test/runtests.jl:1599-1601 and :1616
Claim: the two seam checks in the new "Series helpers" testset have **zero** discriminating
power over the defects their comments cite (U10-5, U10-6); the whole discriminating power
of those two blocks lives in lines 1597–1598 and in the derivative assertion at 1614.
Mechanism: both pre-fix helpers take the *closed* branch at every seam point the test
uses, so they produce bit-identical values to the fixed helpers there. Measured with the
pre-fix implementations re-created in scratch:
`_curv_vers` old vs new at `nextfloat(0.125)`, `0.13`, `0.15` — identical (5.65e-15,
5.89e-15, 4.09e-15), and at `prevfloat(0.125)` the old form scores 6.32e-15, which still
passes the `1e-14` bound. `_sol_log_over_h` old at the 1e-2 seam gives a jump of exactly
`0.0`, so line 1616 passes on the defective code (the old form's real jump, 2.50e-13, is
at *its* 1e-4 seam, which the test never probes). The value assertions at 1613 also pass
on the pre-fix form (7.03e-17 … 9.30e-17 against a 1e-15 bound). This is Measured Lesson 4
in test form: the crossovers `0.125` and `1e-2` are hand-copied literals in the test with
no tripwire, so moving the constant in `src/elements/lattice_magnets.jl:70` or
`src/elements/solenoid.jl:108` makes these lines silently stop straddling anything while
still passing.
Repro: `probe_series.jl` — sections "U10-5" and "U10-6"; compare the `fixed` and `PRE-FIX`
columns. The discriminating lines are the ones where they differ: 1.54e-17 vs 5.86e-9
(line 1597) and 1.63e-17 vs 3.65e-12 (line 1614).

### LEAD U17b-3 [Low-Medium, confidence high] test/runtests.jl:1889
Claim: `@test r.metrics[:checked] > 200` leaves 153 checks (43% of the real count) of
silent headroom, in exactly the shape U16-5 flagged for the AD sweep — which has since
been tightened to zero headroom while this floor was not.
Mechanism: measured `checked = 353`. The contract counts a parameter only when its
perturbed spec compiles and tracks; a perturbation that throws is swallowed by the inner
`catch ... continue` at `src/contracts/Contracts.jl:2118-2123` and never counted, and it
is not reported as ignored either. So a change that makes 150 element-parameter
perturbations invalid narrows the sweep by 43% under a passing report. (Cross-file seam
noted, not pursued: the contract's silent `continue` is the mechanism, and it belongs to
the auditor.)
Repro: `validate(ElementParameterEffectivenessContract()).metrics` →
`Dict(:checked => 353, :ignored => 0, :broken_kinds => 0, :skipped_kinds => 0)`; the
assertion is `> 200`.

### LEAD U17b-4 [Low, confidence high] test/runtests.jl:626-629
Claim: on the Float32 leg, `soft_result ≈ weak_result rtol=32eps(T) atol=32eps(T)` admits
a **0.5% error in the very kick it compares**; the check is 250,000x looser than the
agreement it actually observes.
Mechanism: `isapprox` takes `max(atol, rtol*max(norm(a),norm(b)))`; with `x = 0.4`
dominating the norm, the effective tolerance is `atol = 32eps(Float32) = 3.81e-6`
absolute, while the quantity under test — the difference between the weak-strong map and
`_apply_slice_kick_one!` — lives in `px`, whose total kick is `7.58e-4`. Measured
difference: `1.5e-11`. So the tolerance is 0.50% of the signal. The Float64 leg is sound
(tol/kick = 9.3e-12). A scaled `atol` (e.g. `32eps(T)*abs(kick)`) restores the check.
Repro: `probe_misc.jl` section 2 — `Float32 eta=0.0099834865 max|soft-weak| =
1.4988e-11  tol = 3.8147e-6  |dpx| = 7.5775e-4  tol/kick = 0.00503`.

### LEAD U17b-5 [Low, confidence high] test/runtests.jl:1918 (also :1888, :1897, :44, :57)
Claim: five assertions in the region cannot fail; they are guaranteed by the line above
them or by the call they make.
Mechanism, one by one:
- **1918** `@test r.metrics[:cases] == length(Octopus._ptc_reference_specs())` — the
  contract computes `worst` only for names present in `specs`, then returns a *failure*
  (`Contracts.jl:1876-1880`) if `setdiff(keys(specs), keys(worst))` is non-empty, and that
  failure carries **no metrics at all**. So whenever line 1915's `status === :passed`
  holds, `length(worst) == length(specs)` necessarily. The comment's intent ("every
  declared spec must have been compared") is real and *is* exercised — by the truncation
  mutation control at 1920–1935, which is the line that matters.
- **1888** `metrics[:ignored] == 0` and **1897** `metrics[:broken_kinds] == 0` — both are
  implied by `status === :passed` at 1887 (`Contracts.jl:2132-2137`). The substantive new
  pin in that block is `skipped_kinds == 0`, which is *not* implied.
- **44** `@test Octopus.CUDA.functional()` sits inside `if CUDA_TESTS_ACTIVE`, and
  `CUDA_TESTS_ACTIVE === Octopus._HAS_CUDA && Octopus.CUDA.functional()` (line 40).
- **57** `@test metadata.passed` follows `validate_element_metadata(; throw_on_error=true)`,
  which throws whenever `!passed` (`Knowledge.jl:985-988`).
None of these loses detection (the throw at 57 errors the testset; the neighbouring
mutation controls cover 1918/1888/1897; 44 exists to make a visibility testset non-empty).
The cost is that the assertion count overstates coverage by five.
Repro: read `src/contracts/Contracts.jl:1876-1880` and `2132-2137`, and
`src/knowledge/Knowledge.jl:985-988`; or observe that the region's 1139 passing assertions
include these five under every possible state of the code they name.

### LEAD U17b-6 [Low, confidence high] test/runtests.jl:46-50
Claim: the runtime banner that exists specifically to make CUDA skips visible understates
them by roughly 4x — "Nine CUDA-gated testsets were skipped" against ~35.
Mechanism: `grep -n "if CUDA_TESTS_ACTIVE\|if Octopus._HAS_CUDA" test/runtests.jl` gives
20 gate sites, and the site at line 7133 is a bare `if` wrapping **16 complete testsets**
(7133–7920). The file's own header comment (lines 15–18) already says "more than twenty",
so the file contradicts itself, and the contradiction is on the side a CPU-only user
actually sees. AGENTS.md's rule is "gate skips must be visible"; a visible number that is
wrong by 4x is the failure mode the rule exists to prevent. The named files in the banner
(`pic_cuda.jl`, `gaussian_pic_cuda.jl`, `spectral_cuda.jl`) are likewise no longer the
full list.
Repro: `grep -c "if CUDA_TESTS_ACTIVE" test/runtests.jl` → 9 (3 of them in this region);
`grep -c "if Octopus._HAS_CUDA && Octopus.CUDA.functional()" test/runtests.jl` → 11;
`awk 'NR>=7133 && NR<=7920' test/runtests.jl | grep -c "@testset"` → 16; so 19 gated
testsets plus the 16 inside the block at 7133 ≈ 35, against the banner's "Nine".
(`grep -c "@test_skip" test/runtests.jl` → 18, so most gates do skip visibly now.)

### LEAD U17b-7 [Low, confidence med] test/runtests.jl:2205-2210
Claim: the AD sweep's floor is exact **today** (measured `verified = 25`, headroom 0) but
is written as `>=`, so the comment's claim — "silently losing even ONE element to the
catch above fails" — expires the first time a new differentiable parameter is registered
without the number being raised: one gained plus one lost still passes.
Mechanism: `length(verified) >= 25` with `length(verified) == 25` is a perfect tripwire
now; it degrades silently, because nothing fails when the true count rises. The same
instrument written as equality against a recorded list (or `== 25` with a "raise me"
comment) keeps the claim true and fails loudly on the *addition* too, which is when the
number should be revisited.
Repro: `probe_adsweep.jl` — `verified (25)`, `caught (5)` = exactly
`aperture.x_limit, aperture.y_limit, gaussian_strong_beam.sigz, thin_strong_beam.kbb,
thin_strong_beam.klum` (MethodError/InexactError), matching the in-test comment;
`floor in test is >= 25 ; headroom = 0`.

### LEAD U17b-8 [Low, confidence high] test/runtests.jl:904-909
Claim: the `:equal_area` "closed form" check compares `_gaussian_slices` against an
expression built from the *same* `Octopus.inverse_erf` the implementation calls — measured
difference exactly `0.0` — so for `ns ∈ (3, 7, 15)` it cannot see an error in
`inverse_erf`.
Mechanism: `z ≈ [SQRT2 * inverse_erf(2k/ns) for k in -half:half]` is the implementation's
own formula restated. Backstop, and the reason this is Low rather than Medium: the Furman
Table 1 block immediately above (lines 897–901) pins the same rule at `ns = 5` against
*published* values, measured `dz = 4.34e-7` against a `5e-6` bound — so `inverse_erf` is
independently anchored at five points, and only its behaviour at other `k/ns` ratios rides
on the circular leg.
Repro: `probe_misc.jl` section 3 — `max|z - ref| = 0.0`.

---

## Testset inventory, lines 1–2200

31 testsets open in the region (all top level, no nesting). "Ran" is from
`region_run.log` — the region executed in isolation at `--threads=4` with a functional
CUDA device; pass counts are that run's.

| # | line | testset | what it guards | ran? | would it catch its defect? |
|---|------|---------|----------------|------|----------------------------|
| 1 | 42 | CUDA coverage status | that GPU-half skips are *visible* in the summary | yes (1) | Partly — the mechanism (the `@test_skip` + `@info`) works; the `@test` inside the active branch is tautological (U17b-5) and the banner's numbers are stale (U17b-6) |
| 2 | 55 | Architecture integrity | metadata validity, config metadata, committed registry snapshot | yes (3) | Yes for the snapshot pin (byte equality vs `docs/registry_snapshot.md`); the metadata line is tautological but the throw errors the testset (U17b-5) |
| 3 | 64 | Non-symplectic Lorentz method classification | boosts are declared non-symplectic and compile to the right runtime | yes (13) | Yes — 13 independent type/keyword pins plus a `@test_throws` on a symplectic method |
| 4 | 85 | Linear6D rejects non-symplectic matrices | determinant-only validation would accept a cross-plane shear | yes (17) | Yes — the shear at `[1,3]` has `det == 1` and must be rejected; both spec and raw/runtime paths probed |
| 5 | 146 | Counter RNG smoke tests | Philox determinism, component independence, open-(0,1) mapping | yes (9) | Yes for the mapping (exhaustive 2^23 Float32 sweep, exact endpoint pins); distribution quality is not this testset's job |
| 6 | 190 | TrackingTask smoke test | hooks must not change physics | yes (2) | Yes — `fast == planned` bitwise, plus `fast != initial` non-vacuity |
| 7 | 199 | TrackingTask absolute turns survive chunked execution | counter-RNG keyed on absolute turn, not per-call | yes (12) | **Demonstrated**: restart-keyed proxy defect moves coordinates by 3.2e-3 against a bitwise assertion; motion vs initial is 4.0e-3, so the pin is non-vacuous |
| 8 | 247 | Lumped radiation method and flag semantics | method/flag matrix, long- and infinite-damping limits, invalid input | yes (18) | Yes — `excitation[1] > 0` is the real precision guard; 5 `@test_throws` on invalid input |
| 9 | 336 | Physical and unsafe weak-strong virtual drifts | the 5 drift selectors resolve and reproduce golden outputs | yes (17) | Change-detector only (17-digit golden tuples, class-1 provenance, unchanged since U16); correctness is cross-covered by #14 and #10/#11 |
| 10 | 401 | Round Gaussian near-axis stability | near-axis cancellation in the round kick and its Hessian | yes (20) | Yes — 256-bit BigFloat reference, measured relerr 0.0 at most points, worst 8.1e-8 (Float32) vs a 1.9e-6 bound |
| 11 | 461 | Near-round Gaussian transition | blend window, moments, force/response against quadrature | yes (133) | Yes — independent 96-node Gauss-Legendre reference; Float64 worst 1.45e-11 vs 5e-11, Float32 1.62e-5 vs 3e-5 |
| 12 | 584 | Near-round precision support and tracking consumers | unsupported precisions throw; soft-Gaussian consumer matches the weak-strong map | yes (22) | Float64 leg yes (measured 0.0 vs 7.1e-15); **Float32 leg no** — tolerance is 0.5% of the kick (U17b-4) |
| 13 | 634 | Weak-strong coupled covariance and longitudinal limits | 9 numbered physics claims incl. the invariant Hessian contraction and 6D symplecticity | yes (19) | Yes — measured residual 6.07e-11 vs 2e-8, and items 3/8 agree to exactly 0.0 rel |
| 14 | 759 | Virtual drifts: named three symplectic, unsafe two not | that the symplecticity claim is a proof, not a threshold | yes (10) | Yes — negative control runs every time: safe drifts ratio 100.0 (bound 50–200), unsafe 1.00 and residual 2.05e-5 (bound > 1e-5) |
| 15 | 809 | Conditional 6D Gaussian strong-beam slicing | conditional-Gaussian slope/covariance extraction, crab composition | yes (13) | Yes — `expected_slope`/`expected_conditional` are analytic formulas in the raw inputs, not the extractor's output; pure-crab case pins slope exactly |
| 16 | 873 | Gaussian longitudinal slicing rules | published Furman Table 1, Gauss-Hermite exactness, structural invariants, consumer effectiveness | yes (440) | Yes — worst table deviation 3.57e-6 vs 5e-6 bound; 7 methods × 7 ns invariants; pairwise distinctness non-vacuous. One circular leg (U17b-8) |
| 17 | 1013 | Lattice magnets | symplecticity of 12 magnets, curved-drift closed form, nst/order/curved_order convergence, fringe defaults | yes (71) | Yes — measured convergence ratios 4.01 (bound > 3.5) and 16.08 (bound > 12): an inert `integrator_order` would score 4.01 and fail |
| 18 | 1221 | Named magnet strength keywords | named spellings reach `kn`/`ks` and equal the positional ones bit for bit | yes (58) | Yes — bitwise equality plus 5 `@test_throws` on contradictory spellings; high orders asserted to act (`out[2] != u[2]`) |
| 19 | 1332 | PTC fringe and wedge conventions | PTC's `NMUL<=1`, `BN(1)` drop, `HIGHEST_FRINGE` cap, wedge symplecticity, kill flags | yes (25) | Yes at the element boundary (line 1413 fails if the wedge is neutered); the `_wedge_quad` symplecticity line alone would pass on an identity map (measured motion 7.2e-7) |
| 20 | 1417 | Misalignment maps | frames, conventions, and the "survey follows h not b0" rule | yes (26) | **Demonstrated**: flipping the skew sign in the roll≡skew identity gives 3.08e-4 vs a 1e-15 bound; displacing one quad by dx·(1+1e-9) gives 1.42e-13 vs 1e-15 |
| 21 | 1528 | The bend map is cancellation-free as b0 → 0 | the recorded 1/b0 cancellation (wrong by 1.5e14 at b0=1e-15) | yes (24) | Yes — linear-in-b0 falloff pinned to b0=1e-15 with a documented widening rtol; drift seam exact at b0=0 |
| 22 | 1586 | Series helpers hold full precision across their crossovers (**new**) | U10-5/6/7 removable-singularity defects | yes (24) | **Demonstrated**, partly: pre-fix `_curv_vers` 5.86e-9 vs 1e-15 ✓, pre-fix `_sol_log_over_h` derivative 3.65e-12 vs 1e-13 ✓, pre-fix closed `_wedge` 1.06e-11…5.72e-8 vs 1e-16 ✓. The seam legs catch nothing (U17b-2) and one bound is 1 ulp from red (U17b-1) |
| 23 | 1660 | ref_tilt rolls the design orbit | roll composes outside misalignment; vertical bend == rotated horizontal | yes (23) | Yes — measured 1.36e-20 vs 1e-15 on the axis-exchange identity; roll-vs-body-tilt separation asserted > 1e-6 |
| 24 | 1766 | Thin elements, markers and RBEND | analytic thin kicks, corrector sign, RBEND=SBend+angle/2, thin misalignments | yes (56) | Yes — closed-form kick values and the `k1l*dx` feed-down are analytic references, not self-comparisons |
| 25 | 1881 | Element parameter effectiveness (**changed**) | declared parameters that never reach the map | yes (8) | **Measured**: the new negative control fires — emptying the inactive allowlist returns `:failed` naming `drift.nst` (+8 more). `skipped_kinds == 0` is the substantive tightening; `checked > 200` is slack (U17b-3) |
| 26 | 1913 | PTC coverage cannot narrow silently | a spec added without regenerating the table | yes (4) | Yes — the truncation control executes every run and must fail naming "drift"; the `cases` equality beside it cannot fail (U17b-5) |
| 27 | 1938 | Integrated Green kernel on the axes | the `UndefVarError` on on-axis nodes | yes (8) | Yes — exact `== 0.0` on four on-axis points plus the three `atan` ratio values |
| 28 | 1955 | Luminosity tree reduction power-of-two guard | a non-power-of-two thread count orphaning elements in the reduction | yes (24) | Yes — 6 rejected values, 6 accepted, the inherited-policy path and the rescue override all asserted; **CUDA branch ran here** |
| 29 | 2011 | A launch config a bare collide! cannot apply is not discarded silently | a public tuning surface that silently does nothing | yes (5) | Yes — `@test_logs (:warn,)` on the inert path, no-log assertions on both silent paths, and the composing hybrid type |
| 30 | 2055 | Solver option effectiveness | options that never reach a consumer | yes (6) | Yes — two executed mutation controls (empty alternatives → "no declared alternative"; self-equal alternative → "equal to its own probe value"); `cpu_options_checked` measured 68 vs a `> 60` floor |
| 31 | 2084 | Element parameters carry their own number type (**changed**) | a `Float64` pin that kills differentiability | yes (28) | Yes, and now exactly — measured `verified == 25` against a `>= 25` floor (headroom 0), caught bucket exactly the 5 documented; the swallow is now typed (`MethodError`/`InexactError` only). Floor form is the residual weakness (U17b-7) |

Gates in the region, and what makes them run: three `if CUDA_TESTS_ACTIVE` sites (lines
43, 1983, 2039), each with an `else @test_skip` — the region's skips are **visible**, and
all three took the *active* branch in my run because this box has a functional device.
There are no environment-variable gates, no `try` that swallows a `@test`, no `@test`
inside an uncalled closure, and no loop in the region that can iterate zero times except
the mechanically-guarded ones noted below.

## Clean, with the evidence that makes it checkable

- **Every testset in the region executes and passes at HEAD**: 31/31, 1139 assertions,
  0 fail/error/broken (`region_run.log`). Both CUDA-gated branches executed (the
  luminosity testset's 24 assertions include the 10 that only exist on the GPU leg).
- **Zero-iteration loops**: every `for` in the region iterates over a literal tuple/Dict
  except three — the AD sweep over `registered_element_specs()` (guarded by
  `length(verified) >= 25`, measured exactly 25), the `SLICE_METHODS` loops (measured
  `n = 7`, so the pairwise-distinctness double loop runs 21 times), and
  `for i in eachindex(outs), j in (i+1):length(outs)` at 1097 (literal 4-element list).
  None can silently become vacuous today.
- **U16-1 is fixed**: the `x === nothing || true` tautology at old 1507 is now a typed
  assertion pair (1521–1525) that pins `wrapped.inner` to the same runtime type the
  aligned compile produces.
- **U16-2 is fixed and the fix was measured**: the negative control now empties the
  inactive allowlist and requires `:failed` + `occursin("drift.nst")`. Executed here:
  `status = failed`, message `declared but not consumed: drift.nst, line.L,
  lumped_radiation.alpha, …`.
- **U16-5 is fixed and the fix was measured**: the AD sweep floor is now exact
  (verified = 25, headroom 0) and the bare `catch` is now typed.
- **Tolerance headroom, measured** (value → bound): near-round transition symplecticity
  1.60e-10 → 2e-8 (and an injected non-symplectic map scores 0.133, nine orders above the
  bound); coupled weak-strong symplecticity 6.07e-11 → 2e-8; lattice-magnet symplecticity
  4.44e-16 → 1e-13; misaligned symplecticity 1.11e-15 → 1e-13; `_wedge` symplecticity
  2.22e-16 → 1e-13; roll≡skew 3.47e-18 → 1e-15; rigid displacement 1.08e-19 → 1e-15;
  vertical bend 1.36e-20 → 1e-15; complex-step vs FD 1.62e-11 → 1e-9, 7.19e-10 → 1e-8,
  1.29e-10 → 1e-8; drift `h → 0` limit 7.01e-10 → 1e-8; curved→straight limit 4.66e-7 →
  1e-5; `curved_order` err(6) exactly 0.0 → 1e-13; Furman table worst 3.57e-6 → 5e-6;
  round-Gaussian kick relerr 0.0 → 16eps.
- **`@test_throws` coverage is real, not decorative**: 44 `@test_throws` in the region,
  covering invalid matrices, negative/NaN damping turns, unknown drift selectors, bad
  slice methods, contradictory strength spellings, `misalign_convention=:middle`,
  `highest_fringe=-1`, non-power-of-two luminosity thread counts. All executed.
- **`r.status in (:passed, :skipped)` at line 2061 is sound** (re-verified at HEAD, as
  U16 found at 83e1d38): `Contracts.jl:2568-2572` returns a *failure* for CPU-option
  failures before it can return `:skipped`, so the disjunction cannot hide a CPU
  regression.
- **The chunked-radiation pin is non-vacuous**: motion vs initial 3.99e-3, chunk
  difference exactly 0.0, restart-keyed proxy defect 3.22e-3.

## Informational (not counted as leads)

- `min_cdf_area`'s weight row sits at 71% of its bound (3.57e-6 vs 5e-6). That is the
  published table's own 5-decimal rounding, not slack — but it is the tightest entry in
  the Furman block and the first that would move if the rule's root-finder changed.
- Float32 legs of "Near-round Gaussian transition" (1.62e-5 vs 3e-5) and the moment
  recursion at `nextfloat(2f0)` (2.52e-6 vs 5e-6) sit at 1.85x and 1.98x. Unlike U17b-1
  these carry ~100+ ulp of accumulated error, so single-ulp platform noise cannot flip
  them.
- The unsafe-drift negative control at line 803 (`fine > 1.0e-5`) has 2.05x margin
  (measured 2.05e-5). The ratio test beside it is the decisive one (1.00 vs 100.0).
- Line 1371's `_wedge_quad` symplecticity would pass on an identity map; measured motion
  is 7.2e-7 and line 1413 (`wedge_coeff=(0,0)` must change the map) is the backstop.
- Line 369 `zip(selectors, types, expected)` silently truncates to the shortest of three
  hand-maintained parallel tuples (all length 5 today). A dropped row in `expected` would
  reduce coverage without failing.
- Line 1876 `kd in map(k -> k, summarize_registry().elements)` — `map(identity, …)`;
  style only.
- Lines 1785–1789 and several structural comparisons rely on `≈`'s default `rtol`
  (≈1.5e-8) for maps that are exact in closed form; a relative error below 1e-9 in an
  analytic thin kick would pass. No such defect class is recorded, so this is noted, not
  filed.

## Not checked, and why

- **The CPU-only branch of the three CUDA gates** (the `else @test_skip` legs) was read
  but not executed: this box has a functional device, and forcing the false branch would
  mean editing the file, which a reading unit does not do.
- **The full suite** was not run — the auditor owns that gate. My isolation run covers
  lines 1–2217 only, so it says nothing about interactions with later testsets (e.g. the
  global RNG and knob state this region mutates at lines 235, 1984, 2040, 2142–2162).
  Line 2142's `@knob adsweep_a` registrations persist globally after the testset; whether
  any later testset enumerates knobs is a cross-region seam I did not follow.
- **Provenance of the 17-digit golden tuples at lines 351–367** was not re-derived; they
  are unchanged since U16, which recorded them as class-1 provenance backstopped by the
  symplecticity scan and the BigFloat/quadrature references.
- **`src/contracts/Contracts.jl`'s inner silent `continue`** (2118–2123) is named as the
  mechanism behind U17b-3 but not audited — it is another unit's region.
- **Cross-platform reproduction of U17b-1** (a machine or Julia version where
  `cos(0.13)` differs by one ulp) was not attempted; the mechanism is measured on this
  box by substituting `prevfloat`/`nextfloat` of `cos`, which is an argument about
  sensitivity, not an observation of a second platform.

## Probes

All under
`/tmp/claude-320114/-cfs-ad-dxu/37c712a3-734a-4817-a05e-4c9e12cabcef/scratchpad/audit/`:
`region_1_2217.jl` + `region_run.log`, `probe_series.jl`, `probe_headroom.jl`,
`probe_nearround.jl`, `probe_adsweep.jl`, `probe_contracts.jl`, `probe_misc.jl`,
`probe_abort.jl`, `runtests.diff`, and the scratch project `env/` (repo `dev`ed +
ForwardDiff). Run with
`julia --startup-file=no --project=<audit>/env [--threads=4] <script>`.
