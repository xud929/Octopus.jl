# U16 audit report: test/runtests.jl lines 1-3800

Repo: /cfs/ad/dxu/Library/Julia/Octopus @ 83e1d38 (post-7a8e9ca). Read in full:
lines 1-3812 (the last testset beginning inside the range, line 3765
"StrongStrongTask chunking preserves stochastic physics", closes at 3812; the
next testset begins at 3814 and is outside this assignment).

Coverage: 60 testsets begin in lines 1-3800 (grep '@testset', line numbers
30..3765). Every one was read; leads below; strong-test verifications at the end.
Probes live in .../scratchpad/U16/ and were run from the repo root with
`julia --startup-file=no --project=. [--threads=4] <script>`; all CPU, < 60 s each
after precompile.

## Leads

### U16-1 — test/runtests.jl:1507-1508 — dead assertion (class 8)
```julia
@test compile_runtime(QuadrupoleSpec(L=0.4, k1=1.7, x_offset=1e-3)).inner ===
      nothing || true   # the wrapped element is reachable for inspection
```
`(x === nothing) || true` is a tautology: it evaluates `true` whatever `inner`
holds. The only failure mode left is the field access throwing, so the
assertion pins "a field named `inner` exists", not that it holds the wrapped
element (the comment's claim). Probe: `U16/probe_misc.jl` — prints
`expression value = true (inner isa LatticeMagnet{...})`. Severity: low
(neighbouring assertions in the testset pin the wrap type itself).

### U16-2 — test/runtests.jl:1805-1812 — negative control that cannot fail (class 3)
The block is introduced with "The contract must be able to fail, or it is
decoration", then asserts
```julia
@test validate(bad).status in (:passed, :failed)
```
which admits both outcomes — it can only fail if validate errors or skips. The
in-source comment even concedes the probe "adds nothing to check". The
contract's ability to fail is therefore never demonstrated in this range; the
only other assertion is `haskey(DEFAULT_INACTIVE_ELEMENT_PARAMS, (:drift, :nst))`,
which checks documentation, not detection. A one-line real control exists and
is unused: probe `U16/probe_misc.jl` runs
`validate(ElementParameterEffectivenessContract(inactive=Dict()))` and gets
`status = failed` with message "declared but not consumed: drift.nst,
lumped_radiation.alpha, ...". If the contract's failure path ever regresses
(e.g. failures collected but status still :passed), nothing in this file
notices. Severity: medium.

### U16-3 — test/runtests.jl:3037-3084 — thread-invariance pinned below the threaded threshold (class 4; the U5 pattern, confirmed in-range)
Testset "CPU solver stack is thread-count invariant" runs n=1500 particles and
asserts coordinates bit-identical and pic/gpic luminosity `==` across 1 vs 4
workers. But `_PIC_PARALLEL_DEPOSIT_MIN = 4096` and
`_STRONG_STRONG_PARALLEL_MOMENT_MIN = 4096`
(src/tasks/strongstrong/interface.jl:549-551) gate the threaded PIC deposit
(`pic_cpu.jl:1270,1278,1286`) and the threaded moment reduction
(`slicing.jl:634`) on particle count. At n=1500 (per-slice ~500) both worker
counts execute the identical serial code, so the equality assertions have zero
discriminating power over precisely the cross-worker code the testset's
history (the `_threaded_histogram` Core.Box bug) motivates. Worse, the
headline comment "(kicks are chunk-local, so no cross-worker reduction touches
them)" is false above the gate. Probe `U16/probe_thread_invariance.jl`
(--threads=4):
```
n=1500  pic: identical = true   maxdiff=0.0                    lum_equal=true
n=1500  gpic: identical = true  maxdiff=0.0                    lum_equal=true
n=15000 pic: identical = false  maxdiff=2.52e-15               lum_equal=false
n=15000 gpic: identical = false maxdiff=1.63e-16               lum_equal=false
```
So (a) the threaded deposit/moment paths are never executed by this testset — a
race or shared-box defect there passes; (b) the invariant as stated does not
hold once they do run (the test would fail if merely run at n>=4096, i.e. the
current green is a property of the size choice, not of the stack). The slicing
histogram/partition threading has no size gate and IS exercised at 1500, so
the testset does cover that one family. Sub-note: the comment "Worker count is
a policy knob, so both counts are real even on a single-threaded test run" is
also wrong — `CPUThreadsExecutionPolicy(threads=4)` throws
"CPU threads must be in 1:1" when Julia has one thread (Policies.jl:118), so a
single-threaded suite run aborts loudly in this testset (CI runs --threads=4).
Severity: medium-high.

### U16-4 — test/runtests.jl:2347-2349 — Hessian asserted only symmetric and finite (class 2)
"ForwardDiff differentiates the lattice" item 3 claims nested second
derivatives are "genuinely new coverage", but asserts only
`maximum(abs, H .- H') == 0.0` and `all(isfinite, H)`. Any wrong-but-finite
second derivative passes; no finite-difference or analytic reference for any
H entry. (First derivatives ARE pinned against central differences at
2338-2341; the second-order claim is decoration.) Severity: low.

### U16-5 — test/runtests.jl:2073-2110 — sweep with silent catch and slack floor (class 5)
The registered-element complex-step sweep swallows every error in a bare
`catch` (by design, for aperture/solenoid/near-round), and its guards are
`length(verified) >= 19` plus 9 named kind prefixes. Probe
`U16/probe_adsweep_headroom.jl` measured today: verified = 23 (headroom 4 over
the floor), silently caught = 7 (aperture.x/y_limit, gaussian_strong_beam.sigz,
solenoid.L/ks, thin_strong_beam.kbb/klum — all matching the in-test
rationale), and 11 verified entries lie OUTSIDE the named-kind list:
crab_dispersion.zeta1, hkicker.hkick, lorentz_boost.angle,
momentum_dispersion.eta1, rev_lorentz_boost.angle, thin_rf_cavity.beta0/
frequency/gamma0/strength, vkicker.vkick, xy_coupling.r1. Concretely: a
Float64 pin that makes thin_rf_cavity non-complex-steppable removes exactly 4
entries -> verified = 19 -> `>= 19` still passes and no named kind trips. The
sweep's own comment ("a future Float64 ... shows up here as a lost element")
overstates it for those kinds. Severity: low-medium (fix is a tighter floor or
adding the newer kinds to the named list).

### U16-6 — test/runtests.jl:2825-2832 — silently shrinking CUDA gate (class 5)
The CUDA half of "Slicing degenerate conventions..." (`if CUDA_TESTS_ACTIVE`
with no `else @test_skip`) vanishes without trace on CPU hosts — unlike the
gates at 1907, 1953, 3132, 3495 which skip visibly. The file header (lines
12-27) documents "six are silent" and the top-level "CUDA coverage status"
banner mitigates globally, so this is a known residual, listed for
completeness: the R7 degenerate-slice CUDA convention (slice 1, not slice ns)
is unverified on every CPU run with no per-testset marker. Severity: low.

### Informational (not counted as leads)
- 324-365 "Physical and unsafe weak-strong virtual drifts": the `expected`
  tuples are 17-digit golden values with no independent derivation (class-1
  provenance); they are maximal-power change detectors, and correctness is
  cross-covered by testset 747's symplecticity step-scan and 389/449's
  BigFloat/quadrature references, so not listed as a lead.
- 3591 "PTC consistency" tolerates :skipped (table absent), but 1816 "PTC
  coverage cannot narrow silently" independently requires :passed and equality
  with `_ptc_reference_specs()` — the leniency is backstopped.
- 1958 `status in (:passed, :skipped)` is sound: Contracts.jl:2414-2420 returns
  a failure result for CPU-option failures even when CUDA is absent, and the
  `metrics[:cpu_options_checked] > 60` line errors if the result carries no
  metrics.

## Strong tests (discriminating power verified)
1. 747 "Virtual drifts: the named three are symplectic, the unsafe two are not"
   — real negative controls run every time (unsafe drifts must show a FLAT
   residual > 1e-5) and the step^2 ratio bound (50..200) discriminates
   truncation from structure.
2. 389 "Round Gaussian near-axis stability" — 256-bit BigFloat independent
   reference, rtol 16-32 eps(T), atol 0 for the kick.
3. 449 "Near-round Gaussian transition" — independent 96-node Gauss-Legendre
   reference plus closed-form core gradients at 32 eps; blend endpoints exact.
4. 861 "Gaussian longitudinal slicing rules" — published Furman Table 1
   (including the corrected w2=0.137503), moment-exactness definition of
   Gauss-Hermite, structural invariants over all 7 SLICE_METHODS x 7 ns, and
   consumer-boundary effectiveness (each method must change the tracked kick;
   pairwise distinctness loops verified non-vacuous: SLICE_METHODS has 7
   entries, strong_beam.jl:1245).
5. 1816 "PTC coverage cannot narrow silently" — mutation control executed every
   run: dropping drift rows from a copy of the table must yield :failed naming
   "drift".
6. 3206 "Metadata queries and the validator..." — injected k3_liar meta (fake
   contract, fake analysis, non-compiling example) must FAIL validation with
   three named errors; registry restored and re-validated. This is the repaired
   version of the historical 1-of-13 validator.
7. 1511 "The bend map is cancellation-free as b0 goes to zero" — linear-in-b0
   falloff asserted to b0=1e-15 where the recorded defect was wrong by 1.5e14;
   drift seam exact at b0=0; symplecticity via complex step.
8. 2889 "Curved frame x transverse field" — instrument self-check reproduces
   the recorded defect's analytic magnitude (residual(bad) ~ 2.5e-3, rtol 1e-6)
   before the sweep asserts < 1e-12 on the fixed routings.
9. 1958 "Solver option effectiveness" — two executed mutation controls: empty
   alternatives table must fail ("no declared alternative"), self-equal
   alternative must fail ("equal to its own probe value").
10. 2113 "RF cavity closes the longitudinal plane" — the beta-factor check's
    defect signal (>1e-3, itself asserted at 2178) vs rtol 1e-5, closed-form
    kick in p_t at atol 1e-16, and nu_s ~ sqrt(V) scaling at rtol 1e-6.
11. 1405 "Misalignment maps" — rigid-displacement frame invariance and the
    roll-equals-skew identity are independent physics references at 1e-15.
12. 3765 "StrongStrongTask chunking preserves stochastic physics" — chunked vs
    continuous bit-equality under explicit reseeding pins counter-RNG absolute
    turn keying through a full solver + radiation stack.

## Probes
- U16/probe_thread_invariance.jl (needs --threads=4)
- U16/probe_misc.jl
- U16/probe_adsweep_headroom.jl
