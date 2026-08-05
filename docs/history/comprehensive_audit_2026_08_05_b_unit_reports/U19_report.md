# U19 audit report — test/runtests.jl lines 4400–6600

Repo: `/cfs/ad/dxu/Library/Julia/Octopus`, HEAD `7de4d81`. Host: RTX 4500 Ada,
CUDA 13.0 functional, Julia 1.12.4.

Read: every line of 4400–6600, plus context 4320–4399 (`test_beam`, the testset
whose body precedes the range) and 6600–6660 (the tail of the testset the range
splits); the file header 1–53 (CUDA gating policy + `CUDA coverage status`);
`git diff 6a3f39ab HEAD -- test/runtests.jl` in full; `AGENTS.md` "Hard-Won
Rules"; `docs/comprehensive_audit.md` "Measured Lessons" and "Phase 9";
`docs/history/comprehensive_audit_2026_08_05_unit_reports/U17_report.md`;
and, for mechanism, `src/tasks/strongstrong/slicing.jl:77–91`,
`src/tasks/strongstrong/pic_cpu.jl:449–450`,
`src/tasks/strongstrong/spectral.jl:393–416`.

Provenance marking below: **[read]** = argued from source only; **[measured]** =
a number produced by running code in this session. Probe scripts live in
`<session scratch>/audit/` (`runrange.jl`, `probe_margins.jl`,
`probe_negctl.jl`, `probe_tol.jl`, `probe_corpse_spectral.jl`,
`probe_maxlog.jl`, `probe_lumtol.jl`); the isolated test environment is
`<session scratch>/audit/testenv` (`dev` of the repo + Test/ForwardDiff/Symbolics).

## Coverage

- 40 complete top-level testsets, all at nesting depth 1 (no nested `@testset`
  in the range). 8 are CUDA-gated, 32 are CPU-only.
- Also in range: helpers `nonfinite_test_rep`, `expect_nonfinite_error`,
  `loss_test_coords`, `_LOSS_FIELDS`, `loss_test_rep`, `loss_survivor_rep`,
  `aperture_beam`, `coords_identical`, `wide_aperture`.
- The range boundary at 6600 falls inside the header of
  `"CUDA GaussianPIC coupled subtraction matches CPU"` (opens 6599); it is
  reported here because its opening line is in range.
- **Every one of the 40 testsets was executed in isolation on this GPU host and
  passed** — 30,732 passing assertions, 0 failures, 0 errors [measured]. All 8
  CUDA-gated ones were then re-run with `CUDA_VISIBLE_DEVICES=""` to settle the
  skip-vs-pass question by execution rather than by reading.

## Leads

### LEAD U19-1 [Medium, confidence high] test/runtests.jl:6599 (gate at 6604)
Claim: `"CUDA GaussianPIC coupled subtraction matches CPU"` is the only CUDA gate
in the region with no `else`, and on a GPU-free host it reports **zero tests** —
neither a pass nor a skip — so the summary carries no trace that the only
CPU/GPU parity check for the GaussianPIC *coupled* branch did not run.
Mechanism: the body is `if Octopus._HAS_CUDA && Octopus.CUDA.functional() … end`
with nothing after it. The 2026-08-05 campaign replaced three `else @test true`
green-lies with `else @test_skip` and added one more at 2956, and the file
header now states the rule in its own words ("gated sets without an else still
vanish silently — prefer `else @test_skip` in new ones") — this testset was
missed. Its seven siblings in this region all carry `else @test_skip` and print
`Broken 1`; this one prints `Total 0`. It is one of exactly two remaining
`else`-less gated testsets in the file (the other, line 8451, is outside this
region); the block at 7133 is the 14-testset wrapper covered by the aggregate
skip at line 51.
Repro: with a Test+Octopus environment, on a host with no visible GPU —
```
CUDA_VISIBLE_DEVICES="" julia --project=<env> -e '
using Test, Octopus
CUDA_TESTS_ACTIVE = Octopus._HAS_CUDA && Octopus.CUDA.functional()
L = readlines("test/runtests.jl")
i = findfirst(l -> occursin("CUDA GaussianPIC coupled subtraction matches CPU", l), L)
j = i - 1 + findfirst(==("end"), L[i:end])
Core.eval(Main, Meta.parseall(join(L[i:j], "\n")))'
```
prints `Test Summary: … | Total 0` (measured). Doing the same for
`"Solenoid agrees on CPU and CUDA"` prints `Broken 1` — that is the shape the
rule asks for. With a GPU visible this testset reports `Pass 14` (measured).

### LEAD U19-2 [Medium, confidence high] test/runtests.jl:4733–4776 (Spectral arm)
Claim: the Spectral arm of `"Lost particles cannot influence a strong-strong
collision"` runs in a regime where **21%–100% of the source charge is clipped at
the Dirichlet wall on every solve**, so what it validates about the spectral
field is a degenerate configuration; and it exhausts the process-wide `maxlog=8`
budget of the R9 dropped-charge tripwire, after which that tripwire is silent
for the rest of the Julia process.
Mechanism: the testset's solver list uses `kbb1=kbb2=1.0e-4` with
`test_beam` (`npart = length(rep)` = 4000). The spectral Dirichlet box is sized
once from pre-collision coordinates; at that coupling the intra-collision kick
moves particles well outside it, so `_spectral_deposit_tripwire`
(`src/tasks/strongstrong/spectral.jl:404–412`) fires with
`dropped_fraction` between 0.216 and 1.0. The testset's assertions are
`all(isfinite, values)` plus `values[1]==values[2]==values[3]` across three
corpse variants — all three are clipped identically, so the equality is
satisfied by three equally-destroyed numbers. Separately, `@warn … maxlog = 8`
is tracked per call site per logger: this testset alone emits ≥30 such events
under the process's console logger, so the 8-message budget is spent here.
Repro:
```
julia --project=<env> probe_corpse_spectral.jl     # prints, for Spectral:
#   clip-warnings(corpse arms)=30 frac∈[0.216,1]
#   clip(clean/clean)=10 frac∈[0.216,1]     <- the CONFIGURATION clips, not the corpses
julia --project=<env> probe_maxlog.jl              # prints:
#   tripwire messages emitted under a maxlog-aware logger: 8 (maxlog=8)
#   => after the corpse testset the tripwire is SILENT for the rest of the process
```
Corroboration from the suite itself: running lines 4554–5238 in one process
produced exactly 8 `spectral deposit clipped charge` warnings, every one of them
between the `4733:4776` marker and the next testset (measured,
`cpu_batch1.log`). Whether 4733 is the *first* consumer in full-suite order was
not established (a full-suite run is the auditor's).

### LEAD U19-3 [Medium, confidence high] test/runtests.jl:4778–4841
Claim: `"Lost-particle charge semantics are pinned per solver family"` pins **2
of the 5 solver configurations** its sibling testset (4733) exercises, and the
two it omits are the two whose behaviour a reader would most likely guess wrong:
Spectral renormalizes (like Gaussian) while GaussianPIC keeps the live fraction
(like PIC). Neither is observed by any assertion in the suite.
Mechanism: the testset builds a masked-vs-survivors reference and applies it to
`GaussianPoissonSolver` and `PICPoissonSolver` only. The sibling at 4733 runs
five configurations (PIC, PIC `:sigma`, Gaussian, GaussianPIC, Spectral) and its
own comment states that its corpse-variant equality is blind to charge
normalization by construction. So a silent change to the lost-particle charge
semantics of `GaussianPICPoissonSolver` or `SpectralPoissonSolver` fails nothing.
Repro: `julia --project=<env> probe_tol.jl`, final block — measured
masked/survivors kick-rms ratios against `live_frac = 0.90`:

| solver | kick-rms ratio | luminosity reldiff | masked ≡ survivors bitwise |
|---|---|---|---|
| Gaussian | 1.000000 | 0 | yes |
| PIC | 0.899934 | 1.4e-05 | no |
| PIC `:sigma` | 0.899985 | 1.16e-05 | no |
| **GaussianPIC** | **0.899981** | 1.19e-05 | no |
| **Spectral** | **1.000000** | 0 | no |

The two bold rows are the unpinned ones. The pin's own instrument is sound: a
renormalizing PIC gives ratio 0.999919, which is 111× outside the testset's
`rtol=1.0e-3` (measured, `probe_negctl.jl` NC3).

### LEAD U19-4 [Low, confidence high] test/runtests.jl:5747–5779
Claim: `"PIC kbb override uses physical units"` is circular — the pass is
guaranteed by construction for any *common-mode* defect, which is the defect its
comment implies it guards. (Re-raised: U17-4; unchanged at HEAD.)
Mechanism: `_pic_kbb1(solver,b1,b2) = (solver.kbb1 !== nothing ? solver.kbb1 :
_strong_strong_kbb1(solver,b1,b2)) / length(beam2.rep)`
(`src/tasks/strongstrong/pic_cpu.jl:449–450`), and `_strong_strong_kbb1` returns
`solver.kbb1` when set, else the derived formula (`slicing.jl:77–83`). The test
sets `over.kbb1 = _strong_strong_kbb1(base, e, p)` and then asserts
`_pic_kbb1(over,e,p) == _pic_kbb1(base,e,p)`; both sides reduce to the *same*
expression `phys1 / length(p.rep)`. It therefore tests branch parity, not
kbb's meaning: if `/ length(beam2.rep)` were dropped from both branches (the
"skipped the /n_macro division" the comment names), both sides move together and
both assertions still pass. The end-to-end collision equality at 5771–5778 is the
same comparison.
Repro: read `pic_cpu.jl:449–450` beside `runtests.jl:5765–5770`; no execution
needed. The absolute scale is backstopped only by
`wsl.metrics[:pic_luminosity_relative_error] <= 0.08` far later in the file.

### LEAD U19-5 [Low, confidence high] test/runtests.jl:6341–6365
Claim: the `:node` defining-property block — 18,036 of this testset's 30,053
assertions [measured] — sits behind an unguarded `gb === nothing && continue`
with no premise assertion, so it can shrink to zero silently while
`"PIC interaction_grid flag"` still passes.
Mechanism: `for b in 2:length(s2.boundary)-1 … gb = get_node(b); gb === nothing
&& continue`. If `_pic_node_grid!` ever started returning `nothing` (an empty-slice
guard, a changed memoization key, a different slicing default), every `@test`
inside the loop disappears and the testset reports only its outer 17 assertions
with no signal. The neighbouring union-bounds block does this correctly: it
asserts `@test ub !== nothing` (6314) *before* consuming `ub`.
Repro: `julia --project=<env> probe_margins.jl` prints
`NODE LOOP: boundary len=5, b range=[2, 3, 4], nodes non-nothing=3/3, inner
particle asserts=9018` — today all three nodes materialise; the lead is the
missing tripwire, not a present shrink. Adding `@test count_nodes == 3` (or
asserting `get_node(b) !== nothing` for each `b`) closes it.

### LEAD U19-6 [Low, confidence high] test/runtests.jl:4878
Claim: `@test Octopus.longitudinal_slices(poisoned, sl) isa Any` asserts nothing
about the value — `isa Any` is true of every Julia value including `nothing`.
(Re-raised: U17-8; unchanged at HEAD.)
Mechanism: `poisoned = loss_test_rep(n, dead)` with `dead = [5,137,201]` poisons
`x[5]`, `pz[137]`, `py[201]` — never `z` — so slicing (which reads only `z`)
does not throw and the assertion reduces to "did not throw". That *is* the
comment's intent, but the reader of the summary cannot tell a value pin from a
no-throw pin. `@test_nowarn`/an explicit `!== nothing` and a count check would
say what is meant.
Repro: read; `nothing isa Any === true` in any Julia session.

### LEAD U19-7 [Low, confidence high] test/runtests.jl:5182
Claim: `@test Threads.nthreads(:default) > 1 skip = (Threads.nthreads(:default) == 1)`
can never fail — it is a test whose predicate is the exact negation of its own
skip condition.
Mechanism: at `nthreads > 1` the predicate is true (Pass); at `nthreads == 1` the
`skip` kwarg fires (Broken). No third outcome exists. Read as a *visibility
marker* for the concurrency premise of the `sum(loss_counts(record)) == dead`
assertion three lines below, it is doing its job; read as a test it is
hypothesis-(c) circular. Worth a comment saying which it is, since the block
around it already carries a long NOTE about the concurrency semantics.
Repro: run the testset with `-t1` and with `-t4`; it is Broken-1 then Pass-1,
never Fail (measured for the skip mechanism generally; the `-t4` Pass is in
`cpu_batch1.log`).

### LEAD U19-8 [Low, confidence med] test/runtests.jl:5299–5300 and 5587–5588
Claim: the two `curved = false` warning pins are content-free — `@test_logs
(:warn,)` accepts *any* warning — and each compiles the same spec twice, so the
"ignored" value is not the object whose warning was checked.
Mechanism: `@test_logs (:warn,) compile_runtime(...)` on line N, then
`ignored = (@test_logs (:warn,) compile_runtime(...))` on line N+1 rebuilds it.
A regression that warned about something else entirely (a deprecation, an
unknown-parameter warning from the 2026-08-05 U3-10 work) satisfies both. The
adjacent 2026-08-05 testset `"Straight solenoids differentiate, and
curved=false means straight"` does it right: `@test_logs (:warn, r"curved =
false") match_mode = :any`. Contrast is the evidence that the pattern is known.
Repro: read; compare 5299 with runtests.jl's `r"curved = false"` form (found by
`grep -n 'curved = false' test/runtests.jl`).

### LEAD U19-9 [Low, confidence high] test/runtests.jl:5628–5630
Claim: the cross-implementation solenoid↔SBend reference — U17 rated it one of
the strongest checks in the file — asserts `< 1.0e-6` against a measured
`1.09e-8` (92× headroom), and its comment quotes a number measured at a
different step count than the assertion runs.
Mechanism: the comment (5619–5620) says "measured 6.8e-10 at nst = 1024"; the
assertion at 5628–5630 builds both sides at `nst=256`, where the Strang
truncation is ~16× larger. The bound is then set 92× above what nst=256
actually produces. The guarded structural error (a straight multipole kick in a
curved frame) was 9.6e-4, so the check still fires on its recorded defect — but
anything between 1e-8 and 1e-6 now passes silently, and the comment's number is
not the assertion's number (class 3: comment overstates).
Repro: `julia --project=<env> probe_tol.jl` prints
`5630 cross-implementation SBend vs Solenoid = 1.09e-08 (bound 1e-6, headroom 92x)`.

### LEAD U19-10 [Low, confidence high] test/runtests.jl:5805
Claim: `@test isapprox(lum32, lum64; rtol=1.0e-5)` in
`"GaussianPIC hybrid accepts non-Float64 beams"` is 1,656× looser than the
measured agreement and ~80× looser than `eps(Float32)`, so it cannot detect a
genuine single-precision degradation of the hybrid's luminosity — only a
MethodError, which the surrounding lines already pin.
Mechanism: measured `reldiff = 6.04e-9` between the Float32-rep and Float64-rep
luminosities — far below `eps(Float32) = 1.19e-7`, which says the luminosity
accumulation is already promoted to Float64 internally. A regression that
carried the accumulation in Float32 would land near 1e-7 and still pass
`rtol=1e-5`. The comment's claim ("Float32 inputs, not a new physics") is
therefore pinned about two orders looser than the code currently delivers.
Repro: `julia --project=<env> probe_tol.jl` prints
`lum32=1.0149351e+12 lum64=1.0149351e+12 reldiff=6.04e-09 (rtol 1e-5, headroom 1656x)`.

## Testset inventory (40 testsets, lines 4400–6600)

`Pass` = assertions on this GPU host, measured. `GPU?` = does it need a device.

| line | testset | what it guards | runs? | GPU req.? | catches its defect? |
|---|---|---|---|---|---|
| 4427 | CUDA `:equal_count` under z ties | GPU membership-by-rank vs CPU; CPU exact equal-count under ties | yes (20 GPU / 3+skip CPU) | half | yes — CPU half runs everywhere (U17-5 fixed); GPU half `cg == cc` + membership |
| 4494 | CUDA spectral Dirichlet box honours `allow_lost_particles` | masked box parity, factor-100 defect | yes (6) | yes, `else @test_skip` | yes — rtol 1e-12 vs a 100× defect |
| 4554 | non-finite reporter | error message must not assert what its scan disproved | yes (9) | no | yes — asserts absence of "0 of 3", "index 0" |
| 4597 | non-finite fail-fast at chokepoints | every solver/estimator/grid raises `ArgumentError` | yes (21) | no | yes — 10 independent chokepoints + NaN-schedule non-regression |
| 4665 | `allow_lost_particles` default/scope | scoped flag, six-coordinate liveness | yes (26) | no | yes — all 6 slots × 3 non-finite values |
| 4686 | lost particles excluded from every reduction | survivor-beam reference, atol-only (rtol 0) | yes (11) | no | yes — plus an executed unmasked negative control |
| 4733 | corpses cannot influence a strong-strong collision | corpse-content independence, 5 solvers | yes (15) | no | partly — see U19-2; blind to count-normalization by construction (its own comment) |
| 4778 | lost-particle charge semantics per family | Gaussian renormalizes / PIC live-fraction | yes (5) | no | yes for the 2 it covers (NC3: 111× margin); 3 of 5 configs uncovered (U19-3) |
| 4843 | lost particles dropped from every slicing method | 5 methods × survivor reference | yes (56) | no | yes — exact per-slice membership remap; 4878 is the one vacuous line (U19-6) |
| 4894 | lost-particle masking CPU vs CUDA | device masking in moments + 4 slicing methods | yes (19) | yes, `else @test_skip` | yes |
| 4939 | gathered CUDA PIC routes carry `pz`; `:node` refuses degradation | F10/F11 | yes (11) | yes, `else @test_skip` | yes — CPU parity 1e-13 + 5 refusal paths |
| 5005 | CUDA `last_luminosity` is the final turn's | U7-2, measured 3.0× at turns=3 | yes (2) | yes, `else @test_skip` | yes — rtol 1e-12 vs a 3× defect |
| 5050 | aperture kills what is outside and nothing else | shapes, predicates, offsets, already-dead | yes (22) | no | yes — rect/ellipse/rectellipse discriminated at one corner |
| 5106 | an aperture that kills nothing changes nothing | bit-identity across tracking/WS/4 SS solvers | yes (16) | no | yes — `===` elementwise, premise `count_dead == 0` asserted |
| 5154 | aperture loss record, counter, output | one record per death, per-aperture agreement, HDF5 round trip | yes (21) | no | yes at `-t>1` (concurrency premise made visible, U19-7) |
| 5216 | reconciliation exposes unattributed deaths | dead = logged + unattributed | yes (5) | no | yes — 3 hand-kills, two in coordinates the aperture never reads |
| 5240 | aperture losses identical CPU vs CUDA | private-slot layout ⇒ byte-identical | yes (6) | yes, `else @test_skip` | yes |
| 5276 | curvature resolved before tracking | choice lands in the TYPE | yes (13) | no | yes — type pins + atol 1e-15 curved==straight at h=0 (measured 1.1e-16) |
| 5308 | Patch: change of reference frame | composition direction, MAD-X convention, symplecticity | yes (22) | no | yes — pitch non-invariance ≈ L·θ, convention gap ≈ 0.012·0.3 |
| 5390 | exact solenoid map | closed form solves Hamilton's equations | yes (15) | no | yes — RK4 reference; NC5: losing the Larmor half gives 8.96e-4 vs atol 1e-12 |
| 5471 | solenoid with superimposed multipoles | 2nd-order Strang splitting | yes (11) | no | yes — ratios bracketed 12..20 (measured ≈16) |
| 5518 | solenoid in a curved frame | curved potential, not a straight kick | yes (38) | no | yes — cross-implementation SBend reference (but see U19-9), h→0 first order 10.0035 |
| 5648 | solenoid CPU vs CUDA | device parity 1e-13 | yes (2) | yes, `else @test_skip` | yes |
| 5675 | `TrackingTask` owns the loss record | auto ids, split-run idempotence, per-beam records | yes (20) | no | yes — split vs single-run file equality |
| 5747 | PIC kbb override uses physical units | override path ≠ /n_macro skip | yes (5) | no | branch-asymmetric yes, common-mode **no** (U19-4) |
| 5781 | GaussianPIC accepts non-Float64 beams | G1 MethodError | yes (4) | no | yes for the MethodError; tolerance too loose for precision loss (U19-10) |
| 5810 | shifted moments preserve small spreads | catastrophic cancellation | yes (96) | no | yes — NC6: naive `E[x²]−E[x]²` gives variance 0.0 vs true 1.0, both precisions |
| 5860 | GaussianPIC construction and metadata | schema/registry/validation | yes (13) | no | yes for schema drift; construction-level only |
| 5879 | zero-width GaussianPIC slice | finiteness | yes (3) | no | finiteness only, as claimed |
| 5896 | rank-deficient GaussianPIC falls back to PIC | precision-derived rank test | yes (19) | no | yes for the fallback; the "coupled branch is alive" control lives in the adjacent testset (6643) and on CUDA (6634) |
| 5945 | GaussianPIC beats PIC toward soft-Gaussian | coarse-grid accuracy | yes (2) | no | yes — measured err_h/err_p = 0.8464 vs bound 0.95, bit-stable at 1/4/8 threads |
| 5985 | spectral solver reproduces soft-Gaussian kick | U17-2 fix: kick vectors, not rms of final momenta | yes (4) | no | yes — residuals 0.0169–0.0271 vs bound 0.05; zero/double/flip give 1.0/0.96/2.0 |
| 6028 | spectral CPU workspaces are reentrant | lease pool | yes (42) | no | yes — the U17-6 fix adds a *held-lease* arm that needs no scheduler cooperation |
| 6105 | PIC `field_derivative` flag | default bit-identity, consumer reach, accuracy | yes (9) | no | yes — `errs[:fourth] < 0.75·errs[:second]` against exact Bassetti-Erskine |
| 6172 | PIC `slice_interpolation` flag | default bit-identity, 3 interpolation identities, lazy alloc | yes (28) | no | yes — endpoint collapse, unit transverse weights, zero longitudinal weights |
| 6275 | PIC `interaction_grid` flag | shared-mesh containment, node memoization | yes (30053) | no | yes, but the `:node` half can shrink silently (U19-5) |
| 6368 | PIC `grid_extent` / `grid_quantize` / out-of-range | zero weight outside, top-edge charge, `:sigma` stability | yes (39) | no | yes — NC2: pre-fix top-edge weights `(n−2,(1,0))` fail the `==` |
| 6512 | PIC luminosity overlap sums the full extent | U5-8 truncated overlap sum | yes (4) | no | yes — NC1: truncated sum gives ratio reldiff 7.99e-5 vs rtol 1e-12 |
| 6552 | spectral absolute normalization | derived, not fitted | yes (5) | no | yes — NC4: the recorded 0.982 fitted scale gives needed=1.0194 vs atol 0.005 |
| 6599 | CUDA GaussianPIC coupled subtraction vs CPU | coupled branch device parity | yes on GPU (14); **Total 0** on CPU | yes, **no else** | yes on a GPU host; invisible elsewhere (U19-1) |

## CUDA-gate skip-vs-pass verdicts (settled by execution)

Run on this host with a GPU (`Pass`) and again with `CUDA_VISIBLE_DEVICES=""`
(`no-GPU`):

| testset | GPU | no-GPU | verdict |
|---|---|---|---|
| 4427 CUDA `:equal_count` under ties | Pass 20 | Pass 3, Broken 1 | **honest** — CPU half runs, CUDA half skips visibly |
| 4494 CUDA spectral Dirichlet box | Pass 6 | Broken 1 | **honest** |
| 4894 lost-particle masking CPU/CUDA | Pass 19 | Broken 1 | **honest** |
| 4939 gathered CUDA PIC routes | Pass 11 | Broken 1 | **honest** |
| 5005 CUDA `last_luminosity` | Pass 2 | Broken 1 | **honest** |
| 5240 aperture losses CPU/CUDA | Pass 6 | Broken 1 | **honest** |
| 5648 solenoid CPU/CUDA | Pass 2 | Broken 1 | **honest** |
| 6599 CUDA GaussianPIC coupled | Pass 14 | **Total 0** | **defect (U19-1)** — no pass, no skip, no trace |

No testset in this region reports a *green lie* (the three `else @test true`
cases U17-1 found were all outside 4400–6600 and are fixed at HEAD). The
remaining failure mode here is the silent-vanish at 6599.

## Clean list (audited sound, with the evidence that makes it checkable)

1. **No environment-variable gates.** `grep` over 4400–6600 for `ENV`, `getenv`,
   `Sys.` returns nothing. Every gate in the region is the CUDA one.
2. **No swallowing `try`.** The six `try` blocks in the region are the
   `expect_nonfinite_error` helper (4416), three inline error captures (4569,
   4586, 4883) and two `try … finally` lease releases (6031, 6090). The error-capture
   form assigns the exception and then asserts `err isa ArgumentError`; a
   non-throwing call yields `err = nothing`, which fails. No `@test` is inside a
   `catch`.
3. **No broken `@testset` nesting.** All 40 testsets are depth-1 and balanced;
   each was parsed and evaluated standalone from its `@testset` line to its
   matching `end` without a syntax error.
4. **No zero-iteration loops.** Every loop with a `continue`/`isempty` escape was
   instrumented: the `:node` memoization loop runs 3/3 nodes and 9,018 inner
   iterations; `_pic_union_bounds` returns non-`nothing` with 6,000 inner
   iterations; `widths(:sigma)`/`widths(:extrema)` both return 5 entries;
   `distinct(q)` is self-guarding (an all-skipped run gives `0 < 0`, a failure).
   The one missing *tripwire* is U19-5.
5. **Determinism / thread invariance of the region's margins.**
   `probe_margins.jl` at `-t1`, `-t4` and `-t8` returns bit-identical numbers for
   every quantity it measures (err_h/err_p = 0.846401, spectral residuals
   0.0216164 / 0.0270872 / 0.021761 / 0.016890, relvar ratio 0.09714). Nothing
   in the region is flaky-tight in the thread dimension.
6. **Tolerances measured against their assertions** (assertion → measured →
   headroom):
   - 5400 `atol=1e-15` → 8.72e-17 (11×); 5401 `atol=1e-14` → 1.04e-15 (10×)
   - 5436 axisymmetry `atol=1e-15` → 2.17e-19; 5457 invertibility → 4.34e-19
   - 5295 curved==straight `atol=1e-15` → 1.11e-16 / 1.39e-17 / 1.39e-17
   - 5427 RK4 reference `atol=1e-12` → 5.76e-15 / 1.69e-14 / 1.04e-14 (59–174×)
   - 5531 `atol=1e-7` → 1.42e-9 (h=0.05), 1.75e-8 (h=0.18)
   - 5540 `flat(128) < 1e-7` → 3.19e-8; `flat(8)/flat(32) > 8` → 15.76
   - 5547 `dev(1e-3)/dev(1e-4) ≈ 10 rtol 0.1` → 10.00113
   - 5552 / 5582 bracket `12 < r < 20` → 15.91/16.00/16.06 and 15.76/15.99/16.00
   - 5626 bracket `8 < r < 12` → 10.0035 (k1), 10.0187 (k0s)
   - 5580 `ierr(512) < 1e-8` → 2.0e-9
   - 5981 `err_h < 0.03` → 0.01606; 5982 `err_h < 0.95·err_p` → 0.8464
   - 6023/6024 `< 0.05` → 0.02162 / 0.02709 / 0.02176 / 0.01689
   - 6131 `rtol 1e-3` → 1.72e-4 (6×); 6201 → 1.74e-5 (58×); 6301 → 1.02e-4;
     6335 → 2.64e-4; 6436 `rtol 5e-3` → 1.0e-3 / 6.25e-6 / 1.1e-3 (5×–800×)
   - 6588 `atol=0.005` → 1.05e-3; 6591 `atol=0.002` → 3.2e-5
   None of these passes "regardless of the physics"; the two-sided brackets
   (5552, 5582, 5626) fail for a wrong convergence order in *either* direction.
   The loose ones are called out individually in U19-9 and U19-10.
7. **`atol`-only tolerances are near-exactness pins, not loose ones.** Julia's
   `isapprox` sets `rtol = 0` when a positive `atol` is supplied, so
   `masked.covariance ≈ reference.covariance atol=1e-24` (4701) and its siblings
   at 4700–4703, 4863–4865, 4913, 4929–4930 are strict.
8. **Six negative controls executed, all firing** (`probe_negctl.jl`):
   - NC1 (6512) truncated overlap sum → ratio reldiff 7.99e-5 vs `rtol 1e-12`
   - NC2 (6414) pre-fix top-edge CIC weights `(n−2,(1.0,0.0))` vs asserted
     `(n−1,(0.0,1.0))` for n = 5/16/64
   - NC3 (4778) renormalizing PIC → ratio 0.999919, 111× outside `rtol 1e-3`
   - NC4 (6552) the recorded 0.982 fitted scale → needed 1.0194 vs `atol 0.005`
   - NC5 (5427) map without the Larmor half-angle → 8.96e-4 vs `atol 1e-12`
   - NC6 (5810) naive `E[x²]−E[x]²` → variance 0.0 (true 1.0) in both Float32
     and Float64
9. **The U17 findings that were fixed are fixed, verified by execution.**
   U17-5 (CPU tie-robustness needlessly GPU-gated) — the CPU half now runs on a
   GPU-free host (3 passes measured). U17-2 (rms-of-final-momenta blindness at
   5985) — now compares kick vectors, residuals 0.0169–0.0271 against 0.05.
   U17-6 (best-effort spawned race at 6028) — a deterministic held-lease arm was
   added that needs no scheduler cooperation; the testset reports 42 assertions.
   U17-3's gap was closed for two solver families (4778) but not for the other
   three (U19-3).

## Not checked, and why

- **Full-suite ordering effects.** Every testset here was run standalone or in
  small batches, so cross-testset state (the global RNG, the spectral workspace
  pool, the `maxlog` budget of U19-2, `result/` artefacts) was not exercised in
  suite order. Running the full suite is the auditor's job, per the brief.
- **Whether 4733 is the suite's *first* consumer of the spectral tripwire's
  `maxlog=8` budget.** Establishing this needs a full-suite run; measured only
  that 4733 alone spends the whole budget.
- **MPI agreement (Phase 9 axis).** No MPI test exists in this region.
- **Cross-file seams.** Three noted and stopped at, per the brief: (i) the
  header `@info` at line 48 still says "Nine CUDA-gated testsets were skipped"
  while the region alone holds 8 and the file holds ~24 — stale by ~2.5×, the
  same staleness U17-1 reported against the comment that *was* updated in this
  diff; (ii) the `else`-less gate at line 8451, the file's only other one;
  (iii) `_pic_kbb1`'s absolute scale (U19-4) is backstopped only by the
  `HighEnergyWeakStrongLimitContract` at the end of the file, which U17-7's
  ordering caveat says is the first thing an early abort drops.
- **Precision-change coverage beyond Float32 reps at 5781 and 5810.** No
  Float16/BigFloat path exists to probe.
