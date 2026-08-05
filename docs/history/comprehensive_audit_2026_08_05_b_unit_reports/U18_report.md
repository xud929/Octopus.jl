# U18 audit report — test/runtests.jl lines 2200-4400

Repository: `/cfs/ad/dxu/Library/Julia/Octopus` @ **7de4d81** (HEAD at the time of
reading). Julia 1.12.4; one NVIDIA RTX 4500 Ada present and functional, so
`CUDA_TESTS_ACTIVE == true` for every measurement below unless stated otherwise.

Reading unit for the comprehensive-audit protocol. **Every line of 2200-4400 was
read.** Lines 2200-2217 are the tail of the testset "Element parameters carry
their own number type" (opens at 2084, outside the region); the two assertions
that close it — the `rethrow()` guard and the `length(verified) >= 25` floor —
are inside the region and are covered here. The last testset that opens inside the
region is "Zero-width PIC slice remains finite" (4383-4399); the helper
`nonfinite_test_rep` at 4401 and everything after it is outside.

Provenance is marked per item: **[read]** = inspected only; **[measured]** = a
probe was executed and its number is quoted.

Probe scripts (session scratch, never in the repository), all under
`…/scratchpad/audit/`: `p1_box_sweep.jl`, `p1b.jl`, `p1c.jl`,
`p2_box_injection.jl`, `p2b.jl`, `p3_hsweep_derivation.jl`,
`probe_overwrite_driver.jl` + `OverwriteProbe/`, `p5_misc.jl`,
`u18_p6_adsweep.jl`, `u18_p7_injections.jl`, `u18_p8_spectral_envelope.jl`,
`u18_p9_tolerances.jl`, `u18_p10_latticecells.jl`, `u18_region.jl`,
`u18_region2.jl`. Run as
`julia --startup-file=no --project=<scratch env> [--threads=4] <script>`, where
`<scratch env>` is a throwaway environment that `Pkg.develop`s the repository and
adds ForwardDiff/Symbolics/Test — the suite's test dependencies live in the
package `Project.toml` `[extras]`/`[targets]`, so `--project=.` alone cannot load
the test file.

---

## Leads

### LEAD U18-1 [Medium, confidence high] test/runtests.jl:3134-3207 ("No method grows a Core.Box outside the argued allowlist")
Claim: the permanent `Core.Box` sweep catches **3 of 7** injected boxes — its
candidate enumeration cannot reach 270 of the 2,494 methods Octopus defines, and
the `("validate", "Contracts.jl")` allowlist entry blankets 24 methods while the
argument beside it justifies exactly one.
Mechanism: the sweep collects candidate functions with
`names(Octopus; all=true, imported=false)`. Every method Octopus adds to a generic
**owned by another module** is therefore invisible — the binding lives in
`Base`/`Adapt`, not in `Octopus`, so `getfield(Octopus, name)` never yields the
function even though `m.module === Octopus` holds for the method. Measured: the
sweep sees 2,224 methods; a scan over every loaded module's names finds 2,494
methods with `m.module === Octopus`; the 270-method difference is `Base.show` (7),
`Base.==` (5), `Base.getindex` (5), `Base.hash` (5), `Base.+ - * /` (12),
`Base.propertynames`/`getproperty`/`setproperty!` (12), `Base.read`, `Base.length`,
`Base.lastindex`, `Adapt.adapt_structure` (3), plus the auto-generated
`Core.kwcall` sorters (skipped by `f isa Core.Builtin && continue`). **None of the
270 carries a box today**, so the sweep is genuinely clean at HEAD — it is blind,
not wrong. Second mechanism: the allowlist key is `(clean_name(m), file)`, and
`clean_name` folds closures (`#validate#N` → `"validate"`) onto the same key, so
one entry exempts a whole family; 24 methods in `Contracts.jl` match
`clean_name == "validate"` and exactly 1 of them boxes today. `@test nmethods > 2000`
cannot see either gap (2,224 > 2,000).
Repro: `julia --project=<scratch env> p2_box_injection.jl` →
`INJECTION RESULT: 3 of 7 caught`. MISSED: a new `validate` method in
`Contracts.jl` carrying a box, a closure inside such a method, a boxed `Base.show`
method, a boxed `Base.==` method. CAUGHT: a plain new Octopus function in a
non-allowlisted file, a keyword method's body, a differently-named function in the
allowlisted `Beam.jl`. Coverage numbers from
`julia --project=<scratch env> p1_box_sweep.jl`:
`sweep as written: nmethods = 2224 / global scan: 2494 / MISSED: 270 /
MISSED methods that DO carry a Core.Box: 0` and
`(validate, Contracts.jl): 24 methods match the pattern, 1 of them currently box`.

### LEAD U18-2 [Medium, confidence high] test/runtests.jl:3209-3288 ("CPU solver stack is thread-count invariant")
Claim: the second (above-threshold) block is a hand-copy of the first block's
solver list with one entry dropped, and the dropped entry — `spectral_t` — is
exactly the solver whose luminosity is **not** bit-invariant across worker counts.
Measured at n=15000: `spectral_t` luminosity differs by 8.0 between 1 and 2 workers
at nslices=3, and by 16.0 between 1 and 2 **and** between 1 and 4 workers at
nslices=15 (relative 1.7e-16 / 2.66e-16, ~1 ulp). `pic`, `gpic` and `spectral_l`
are bit-identical at every count and slice count tested (3, 5, 9, 15), coordinates
and luminosity alike.
Mechanism: block 1 (line 3237) lists `pic, gpic, spectral_t, spectral_l`; block 2
(line 3263) lists `pic, gpic, spectral_l`. Nothing in the code or comments records
the omission, while the block header (3216-3222) states "The reductions now use
FIXED chunk grids with the serial/chunked choice made by data size only, so the
second block below pins full bit-equality — luminosity included". That claim does
not hold for the spectral transverse path: `src/tasks/strongstrong/spectral.jl`
still partitions its luminosity fold by the live worker count
(`nchunks = clamp(_cpu_worker_count(), 1, max(n1, n2))` at ~1000;
`max_workers = clamp(_cpu_worker_count(), …)`, `nworkers = clamp(max_workers, 1,
length(batch))`, `_chunk_bounds(length(batch), nworkers, chunk)` at ~1103) — unlike
the PIC deposit and the moment reduction, which use the fixed `_PIC_DEPOSIT_CHUNKS`
/ `_REDUCTION_CHUNKS` grids (`interface.jl:570-581`). **Cross-file seam flagged and
not pursued**: whether the spectral fold should be made count-invariant or the
pin's claim narrowed is the auditor's call.
Sub-note (same block): the header says "for 1/4/8 workers"; the code runs
`counts = unique((1, 2, Threads.nthreads(:default)))` = `[1, 2, 4]` at CI's
`--threads=4` (measured). The inline comment at 3270-3273 states this correctly;
the header does not.
Repro: `julia --project=<scratch env> --threads=4 u18_p8_spectral_envelope.jl` →
`spectral_t nslices=15  workers 1 vs 2: lum_eq=false coords_eq=true
coord_maxdiff=0.0 lum_absdiff=16.0`.

### LEAD U18-3 [Low-Medium, confidence high] test/runtests.jl:4252-4256, 4270-4274 ("Lattice cells track and stay symplectic")
Claim: three CPU↔CUDA agreement checks are asserted as
`status in (:passed, :skipped)` with no CUDA gate and no skip marker, so on a
GPU-less host they count as ordinary **passes** and the test summary is byte-for-byte
indistinguishable from a real GPU run.
Mechanism: the F20 class in its subtler form — not an `if CUDA_TESTS_ACTIVE` block
that vanishes, but a tolerant status assertion.
`validate(::ElementTrackingBackendConsistencyContract)` returns `:skipped` **only**
when a backend is unavailable (`src/contracts/Contracts.jl:640-646`), so on a
CPU-only host all three assertions are vacuous by construction. One of them
(`stochastic_gpu`, 4270-4274) is the only place in the whole file that compiles a
counter-RNG element into the fused CUDA kernel — the U15-4 device-IR regression its
own comment describes — so on CI it is pure decoration reported as a pass. Contrast
line 3784, which does it correctly:
`@test rp.status === :passed || (rp.status === :skipped && !CUDA_TESTS_ACTIVE)`.
Repro: `env CUDA_VISIBLE_DEVICES="" julia --project=<scratch env> --threads=4
u18_p10_latticecells.jl` (lines 4202-4275 extracted verbatim) →
`CUDA functional = false` and `Lattice cells track and stay symplectic | 35 35`.
The same testset on the GPU host also reports `35 35` — same count, zero skips,
zero broken, in both cases.

### LEAD U18-4 [Low, confidence high] test/runtests.jl:3014-3085 ("Curved frame x transverse field: every routing is a gradient")
Claim: the permanent h≠0 symplecticity sweep does **not** derive its case list; the
"derived, not assumed" claim in its own comment is a hand-assertion with no
tripwire, so a newly registered kind carrying both curvature and field would be
swept by nothing and fail no test.
Mechanism: the comment at 3020-3022 says "this pins the whole content grid on the
only two kinds whose schemas offer both curvature and field (derived, not assumed:
no other registered kind carries both)". Nothing in the testset computes that set;
the cases are a literal `contents` vector of `SBendSpec`/`SolenoidSpec`
constructions plus one raw `ElementSpec{:quadrupole}` with an undeclared `h`. The
claim is **true today** — measured across all 30 registered kinds, exactly
`[:sbend, :solenoid]` carry both a curvature key (`h`/`curved`/`b0`) and a field key
(`kn`/`ks`/`kskew`/`k1`…), with `drift` carrying curvature only — but that is a fact
about HEAD, not an invariant the suite maintains. The right shape sits one testset
away: line 3741 asserts `r.metrics[:kinds_declaring_without_case] == 0`, a real
declaration→coverage tripwire on `SymplecticityContract`, with an executed
`symp_liar` negative control at 3747-3758.
Repro: `julia --project=<scratch env> p3_hsweep_derivation.jl` →
`kinds carrying BOTH curvature and field in their schema: [:sbend, :solenoid]`;
`NOT swept but carrying both: Symbol[]`.

### LEAD U18-5 [Low, confidence high] test/runtests.jl:3718-3720 ("Unknown spec keys warn…")
Claim: the comment promises a check ("match the message and check the kwarg
below") that does not exist anywhere in the testset; the unknown-parameter
warning's payload — the offending key — is never asserted.
Mechanism: `@test_logs (:warn, r"unknown parameter")` matches the message string
only. Measured, the message is `"ElementSpec{:quadrupole}: unknown parameter(s)
stored as descriptive metadata only — if one is a typo of a physics parameter, it
is NOT being tracked. Deliberate metadata can use set_param! to stay silent."` and
contains neither `this_keyword_does_not_exist` nor `bogus`; both travel in the
structured kwarg `unknown = [:…]` (`src/knowledge/Knowledge.jl:100`). The lines
after 3720 test placement-key silence, `MisalignedElement` compilation,
`_spec_epoch`, and `set_param!` — none inspects the kwarg. A regression that warned
without naming the key (the whole point of the U3-10 fix) would still pass.
Repro: `julia --project=<scratch env> u18_p9_tolerances.jl`, first section, which
renders the full log record through a `ConsoleLogger`: the key appears only inside
the `unknown = …` kwarg block. `@test_logs` compares its `Regex` against
`record.message` alone, which does not contain it — so `r"unknown parameter"`
would still match a warning that had lost the key list entirely.

### LEAD U18-6 [Low, confidence med] test/runtests.jl:2876-2879 ("Observer finalizers, BPM noise keys, and the schedule planner", T10)
Claim: `@test @elapsed(Octopus._scheduled_turns(s, 5, 10^8)) < 0.005` is a
wall-clock assertion inside a file that aborts at its first failing testset.
Mechanism: the measured cost is 8.8e-8 … 4.2e-6 s (>1,000x headroom), so it is a
sound complexity guard; but a GC pause, a preempted shared CI runner, or first-call
compilation on a future Julia can exceed 5 ms, and because this file aborts at the
first failure (documented in its own header as U17-7), a single flake here silently
drops every testset after line 2879 — including the whole CUDA block and the
end-of-file physics backstops.
Repro: `julia --project=<scratch env> --threads=4 p5_misc.jl`, section (4):
`@elapsed samples = [4.208e-6, 2.92e-7, 8.8e-8, 2.41e-7, 1.2e-7]`.

---

## Injection results (hypothesis d and c)

| what was injected | testset | result |
|---|---|---|
| 7 `Core.Box` closures (plain fn; new `validate` in Contracts.jl; closure inside such a method; `Base.show`; `Base.==`; keyword-method body; different name in allowlisted `Beam.jl`) | 3134 Core.Box sweep | **3 of 7 caught** (LEAD U18-1) |
| worker-count-dependent chunk partition (`_chunk_bounds` redefined to shift boundaries by `_cpu_worker_count()-1` — the pre-fix U5-1/2 class) | 3209 thread-invariance | **2 of 3 solver legs caught**: `pic` coords 2.5e-15 / lum Δ170, `gpic` coords 1.4e-16 / lum Δ2; `spectral_l` unaffected because its chunking runs through `_cpu_worker_count()` in `spectral.jl`, which the injection did not touch |
| same-signature method overwrite in a scratch package, driven through `Base.compilecache` exactly as the test drives it | 3411 method-overwrite guard | **2 of 2 message patterns fire** on Julia 1.12.4 (`Method overwriting is not permitted` and `Method definition .* overwritten`), and `success(p) == true` — confirming the in-test comment that the exit code carries no signal and the assertion must be on the message |
| Philox with 3 rounds; Philox with the Weyl key bump removed | 3873 Philox KAT | **2 of 2 caught** (both fail the three KAT vectors; the as-shipped implementation passes) |
| an undocumented export; an export whose docstring is detached by an intervening comment | 3397 export documentation | **2 of 2 caught** (`[:u18_no_doc_export]`, then `[:u18_detached_export, :u18_no_doc_export]`) |

Injections already **executed by the suite itself on every run** (verified present
and effective, no scratch work needed): the h≠0 sweep's instrument self-check
(`residual(bad)` measured 0.0025000000000000005 against
`isapprox(2.5e-3; rtol=1e-6)`), the `k3_liar` metadata liar (3485-3494), the
`symp_liar` declaration→coverage tripwire (3747-3758), the broken-baseline probe
(3763-3769), the probe-less-solver refusal (3773-3778), and the two spectral
charge tripwires (`@test_logs (:warn, r"clipped charge…")`, `r"grid_free source
outside…"`, 3001-3011).

---

## Testset inventory (region 2200-4400)

40 testsets open inside the region, plus the tail of one that opens before it.
"Runs" was established by executing the region in two halves — `u18_region.jl`
(lines 2219-4399) and `u18_region2.jl` (lines 3356-4399, with the two
`dirname(@__DIR__)` paths repointed at the repository; that is the only edit, and
it is needed because the extracted file sits outside `test/`). Assertion counts are
from those runs on the GPU host.

| line | testset | guards | runs | catches its defect |
|---|---|---|---|---|
| 2084→2217 | Element parameters carry their own number type *(tail only)* | a `Float64` pin that silently drops an element from complex-step differentiability | yes, unconditional | yes — measured `verified = 25` against `>= 25`, **zero headroom**, so losing one element fails; caught bucket is exactly the 5 documented (aperture.x/y_limit, gaussian_strong_beam.sigz, thin_strong_beam.kbb/klum); the new `rethrow()` closes the bare-catch hole |
| 2219 | RF cavity closes the longitudinal plane | a cavity formula lifted from another longitudinal convention (missing 1/β) | yes, 33 asserts | yes for protons — the testset itself pins the signal at >1e-3 vs rtol 1e-5; the electron case is knowingly powerless and says so |
| 2326 | Longitudinal conventions convert exactly | non-exact / non-symplectic convention conversions | yes, 149 asserts | yes — 96 round trips at <1e-15, 36 unit-determinant Jacobians at <1e-14, `s`-offset isolation with a >1e-6 non-vacuity guard |
| 2405 | ForwardDiff differentiates the lattice | a Float64 pin that breaks dual propagation; a wrong-but-finite Hessian | yes, 15 asserts | yes — Hessian columns pinned to central FD of the gradient (measured 3.8e-9/2.1e-9/6.7e-13 vs rtol 1e-5); symmetry tolerance 1.78e-15 vs measured asymmetry 4.34e-19 (4096x) |
| 2509 | BeamLine composes, addresses and tracks | container semantics changing physics; shared-spec/private-placement leaks | yes, 43 asserts | yes — bit-equality vs the bare tuple, rigid-girder invariance at 1e-15 with a >1e-6 non-vacuity guard |
| 2635 | Loss accounting reports itself | silent loss reporting, unattributed losses, dropped arc positions | yes, 22 asserts | yes — the positive `occursin("2 of 4 particles lost")` protects the three `isempty(...)` silence assertions from a broken stdout capture |
| 2738 | Every walker over the line agrees on what a container is | T1/T3/T4/T5 walker divergence (nested vectors, LineEntry) | yes, 15 asserts | yes — each assertion is stated to fail on the pre-fix code; `_aperture_specs == 2`, `loss_counts == [1,1]`, `unattributed == 0` |
| 2817 | Observer finalizers, BPM noise keys, and the schedule planner | stranded finalizers; retroactive noise; absolute-turn planner cost | yes, 2011 asserts | yes — 2,000-case oracle equivalence for the planner; noise pinned to `octopus_normal` with explicit keying. Timing assertion → LEAD U18-6 |
| 2889 | A crashed execute! still delivers its loss artifacts | T6a/T6b: unflushed loss file, duplicated turn labels on retry | yes, 9 asserts | yes — `readings(bpm)[1] == [0,1,2]` before and after the retry |
| 2933 | Slicing degenerate conventions and the spectral charge tripwire | R7 per-backend slice convention; R9/R10 silent charge loss | yes, 10 asserts (CUDA half visible as `@test_skip` on CPU) | yes — `whichslice(...) == [1]` would read `[4]` on the old convention; both tripwires are `@test_logs (:warn, …)` |
| 3014 | Curved frame x transverse field | h≠0 non-gradient routing | yes, 31 asserts | yes — executed instrument self-check reproduces the recorded 2.5e-3 defect every run; worst content case measured 4.44e-16 vs `< 1e-12`. Case-list derivation → LEAD U18-4 |
| 3087 | Straight solenoids differentiate, and curved=false means straight | F17: complex-typed straight-solenoid body; `curved=false` storing raw h | yes, 9 asserts | yes — pre-fix it errors rather than fails; measured residuals 1.8e-16/5.6e-16 vs `< 1e-10`, `sol_cf.h == 0.0`, exact map equality |
| 3134 | No method grows a Core.Box outside the argued allowlist | a concurrent-closure box (the `_threaded_histogram` trap) | yes, 2 asserts | **partially — 3 of 7 injected. LEAD U18-1** |
| 3209 | CPU solver stack is thread-count invariant | worker-count-dependent reductions | yes, 30 asserts; n=15000/3 slices = 5000 per slice, above the measured `_PIC_PARALLEL_DEPOSIT_MIN`/`_STRONG_STRONG_PARALLEL_MOMENT_MIN` = 4096 | yes for pic/gpic (2 of 3 legs on injection). **Coverage gap → LEAD U18-2** |
| 3290 | CUDA equal_area histogram matches the CPU membership rule | U2-2 membership divergence between kernel and CPU `_slice_bin` | yes on GPU (8 asserts); `@test_skip` on CPU | yes — the kernel *inlines* a transcription of `_slice_bin` (`pic_cuda.jl:5271-5286`), it does not call it, so the oracle is a transcription check, not a circularity |
| 3336 | Spectral solve/eval split is exact | R12 refactor changing results | yes, 2 asserts | yes — bit equality `Ex1 == Ex0`, `Ey1 == Ey0` |
| 3356 | Every example script runs against the current interface | examples silently broken by refactors | yes, 5 subprocess runs (3m38s) | yes — exit code 0 is the assertion, with the output tail surfaced |
| 3397 | Every export is documented | undocumented exports; comment-detached docstrings | yes, 1 assert | yes — **2 of 2 injected caught** |
| 3411 | The module precompiles without overwriting its own methods | a silent same-signature method overwrite | yes, 3 asserts (17.5 s here) | yes — **2 of 2 message patterns fire** on Julia 1.12.4; `@test success(p)` carries no signal (it is `true` even on the failing precompile), as the comment states |
| 3432 | Metadata queries and the validator check declarations, not themselves | K2/K3/K5/K6/K8; the historical 1-of-13 circular validator | yes, 16 asserts | yes — `k3_liar` executed every run, three named errors required, registry restored and re-validated |
| 3506 | StrongStrongTask luminosity_append continues one file | replace-vs-append semantics, stale rows, header mismatch | yes, 5 asserts | yes — exact turn lists `[3,4,5]`, `0:6`, `0:4`, one header, `ArgumentError` on mismatch |
| 3561 | Mixed-IP schedule rows drop loudly; solver equality is by configuration | U4: corrupt partial `.lum` rows; identity-based solver comparison | yes, 4 asserts | yes — `@test_logs (:warn, r"luminosity row dropped")` plus the exact surviving row list `[0]` |
| 3615 | MomentObserver append mode continues one table across executions | append/replace/restart/idempotence/column-mismatch | yes, 8 asserts | yes — exact turn lists at each stage, two `ArgumentError` refusals |
| 3671 | Nested lines have length, reflection keeps state, folded sugar is rejected everywhere | U11-1/2/3/4/8 | yes, 9 asserts | yes — `s_positions == [0.0, 1.4]`, `total_length == 2.4`, warning on a hidden aperture plus a silence assertion on the visible one |
| 3704 | Unknown spec keys warn, placement keys bind, set_param! bumps the epoch | U3-10/U13-1/U13-2 | yes, 6 asserts | partially — the warning is required but its payload is not. **LEAD U18-5** |
| 3731 | Contract coverage guards: declared kinds, solver tree, broken baselines, unrun contracts | U3-3/4/6/7 | yes, 15 asserts (1m42s) | yes — three executed negative controls (`symp_liar`, throwing baseline → `broken_kinds == 1`, probe-less solver), and `PublicConfigurationEffectivenessContract` measured `:passed` here |
| 3793 | The elliptical strong-beam kick differentiates | U7-1: η≠0 Bassetti-Erskine throwing under ForwardDiff | yes, 1 assert | yes — pre-fix it *errors*; measured residual 4.46e-12 vs `< 1e-10` (22x headroom) |
| 3815 | Every continuing observer drops its replayed window | U6-2: four observers duplicating turn labels | yes, 4 asserts | yes — each file's turn list read back and compared to `0:4` / record count 3 |
| 3873 | Philox4x32-10 matches the Random123 known-answer vectors | a statistically-plausible but wrong Philox | yes, 4 asserts | yes — **2 of 2 injected caught** (3-round and no-Weyl variants both fail) |
| 3899 | Wrapped stochastic elements keep their context, shared streams warn, unbound apertures cannot corrupt | F13/F14/F15 | yes, 5 asserts | yes — bit-repeatability through the wrapper, duplicate-placement warning plus a single-placement silence assertion, `counts == Int32[1]` |
| 3943 | Append continuation: torn writes dropped, corruption refused, wipes loud | F1, U4-1/2, U6-1, A-5 | yes, 8 asserts | yes — three `@test_logs (:warn, …)`, one `ArgumentError`, exact turn lists |
| 4023 | A task re-run on the other backend reallocates its loss record | T2: a loss record compared by shape, not backend | GPU only; `@test_skip` on CPU (5 asserts here) | yes on a GPU host — asserts the record's array type flips both ways |
| 4051 | BPM reads a device number, not the truth | inert BPM error terms; shared noise streams; chunking | yes, 28 asserts | yes — 9-parameter effectiveness loop (`moved != base`), MAD-X closed form, chunked-vs-continuous equality |
| 4143 | PTC consistency | drift from the committed PTC reference | yes, 49 asserts; measured `:passed`, `cases = 55` | yes — 45 `dev_*` metrics pinned **by name** (a KeyError if any vanishes) at `< 1e-11`; the `cases >= 36` slack is backstopped by "PTC coverage cannot narrow silently" (line 1913, outside region), which requires `:passed` **and** `cases == length(_ptc_reference_specs())` with an executed truncation control |
| 4202 | Lattice cells track and stay symplectic | non-symplectic composed cells; CPU/CUDA divergence; device-IR regressions | yes, 35 asserts | CPU half yes (measured residuals 6.7e-16 … 1.2e-15 vs `< 1e-12`); **GPU half vacuous on a CPU host → LEAD U18-3** |
| 4277 | Configuration rejection | invalid policy construction accepted | yes, 3 asserts | yes — three `@test_throws ArgumentError` |
| 4283 | Phase-space and element boundary validation | ragged reps, empty beams, non-finite crab strengths | yes, 7 asserts | yes |
| 4299 | Equal-count slicing permits empty slices | an empty slice crashing or dropping a particle | yes, 4 asserts | yes — `sum(length, indices) == 1`, sorted finite boundaries |
| 4308 | MomentObserver task reuse | re-initialisation on reuse; lost record count | yes, 4 asserts | yes |
| 4334 | StrongStrongTask chunking preserves stochastic physics | absolute-turn RNG keying broken by chunking | yes, 12 asserts | yes — bit equality of all six coordinate arrays of both beams |
| 4383 | Zero-width PIC slice remains finite | NaN/Inf from a degenerate slice | yes, 3 asserts | weakly, by design — finiteness only; it is a crash guard, not a value guard |

Region totals on this host: **41 units, every one executed, every one green** —
2,389 assertions across the 15 testsets from 2219 to 3336, and 244 across the 25
testsets from 3356 to 4399. The only failure observed was the example-script
testset in the *extracted* first-half script, an artifact of `@__DIR__` pointing at
the scratch directory; the same testset passes 5/5 once the path is repointed at
the repository.

---

## Clean list (audited sound, with the evidence that makes it checkable)

1. **Every CUDA gate in the region skips visibly.** `if CUDA_TESTS_ACTIVE … else
   @test_skip` at 2946/2956, 3298/3332, 3785/3789, 4028/4047, and the correctly
   conditioned `rp.status === :passed || (rp.status === :skipped &&
   !CUDA_TESTS_ACTIVE)` at 3784. The U16-6 silent gate at old-line 2825 is closed.
   The one remaining silent-CUDA construct is LEAD U18-3, which is a tolerant
   status assertion rather than a gate.
2. **No environment-variable gates.** `grep -n "ENV"` over 2200-4400 returns
   nothing; no testset in the region can be skipped by an unset variable.
3. **No zero-iteration loops.** Every `for` in the region iterates over a literal
   tuple/vector or a computed range with a non-vacuity assertion beside it:
   the AD sweep's kind list (9), the h≠0 `contents` grid (10, with a documented
   `isempty(pairs(kw)) && continue` skipping only the pure curved solenoid, which
   the dedicated pair at 3080-3081 asserts at the right tolerances), the thread
   pin's solver lists (4 and 3), the planner oracle's 2,000-case product
   (`4×4×5×5×5`), the BPM error-term loop (9), the PTC key list (45), the CUDA
   histogram cases (4), the observer loops. `for other in 2:length(outs)` at 3282
   always runs at least once because `counts` has ≥2 entries.
4. **No `@test` inside a swallowing `catch` in the region.** The two `try` blocks
   (3473-3502, 3747-3758) are `try/finally` registry-restore blocks; the sweep's
   `try/catch` at 3174-3195 catches only around `getfield`/`methods`/
   `uncompressed_ir` and contains no assertions. The AD sweep's `catch` at 2190
   now `rethrow()`s anything that is not a `MethodError`/`InexactError` — measured,
   the 5 swallowed cases are exactly the 5 the comment names.
5. **No circular tests found.** The three candidates were checked and cleared:
   (a) the CUDA histogram oracle at 3299-3307 calls `Octopus._slice_bin`, but the
   kernel *inlines a hand transcription* of it (`pic_cuda.jl:5271-5286,
   `unsafe_trunc` vs `floor(Int, …)`), so the comparison is transcription-vs-source,
   not a function against itself; (b) the planner oracle at 2864-2869 is an
   independent enumerate-and-filter; (c) the BPM/T8/T9 noise pins compare the
   observer's draw against `octopus_normal` called with explicit keying arguments,
   which pins the *keying*, while the generator itself is pinned independently by
   the Philox KAT block against upstream Random123 vectors.
6. **`@test_logs` silence assertions are real.** 2733, 3700-3701, 3721, 3931 use
   `@test_logs expr` with no patterns and the default `:all` match mode, i.e. they
   assert that *no* log record is emitted — they are not decorative.
7. **Tolerance headroom, measured (assertion → measured value → headroom):**
   `H .- H'` 1.78e-15 → 4.34e-19 (4096x); Hessian FD columns rtol 1e-5 → 3.8e-9
   (2600x); SBend h≠0 grid `< 1e-12` → worst 4.44e-16 (2250x); curved solenoid
   nst=4 `< 1e-8` → 1.112e-9 (9x, and the documented convergence floor is 1.1e-9);
   curved solenoid nst=16 `< 1e-12` → 1.11e-16; `curved=false` `< 1e-9` → 5.55e-16;
   straight solenoids `< 1e-10` → 1.8e-16 / 5.6e-16; elliptical strong-beam kick
   `< 1e-10` → 4.46e-12 (22x); lattice cells `< 1e-12` → 6.7e-16 … 1.2e-15 (~1000x);
   RF-cavity `nu_s` ratios rtol 1e-6 → 6.7e-9 and 3.05e-8 (147x and 33x, and the
   deviation is the physical `O(nu_s^2)` term, so it is calibrated to the chosen
   voltages rather than to noise); BPM noise statistics 4,000 deterministic
   counter-RNG draws (no flake channel). None of these is loose enough to pass
   regardless of the physics; the two tightest (curved solenoid nst=4 at 9x,
   elliptical kick at 22x) are deterministic, not statistical.
8. **The `>= 25` AD floor is a genuine zero-headroom pin.** Measured `verified = 25`.
   This is by design ("today's exact count … never lower it"); it is a hand-
   maintained number, but as a floor it can only fail to notice an *addition*, never
   pass a *loss*. The U16-5 finding (floor 19 with headroom 4) is closed.
9. **The four permanent sweeps all still run and all still carry arguments.** The
   `Core.Box` allowlist has seven entries in four argued groups (serial file I/O,
   serial contract helpers, a serial constructor, one-shot adapter activation, and
   the one concurrent-closure box in `_spectral_collide_longitudinal!` with a
   three-line benign-ness argument naming the refactor that would break it); the
   thread pin now runs above the 4096 thresholds; the method-overwrite guard's
   instrument is verified on this Julia; the h≠0 sweep's instrument self-check
   reproduces the recorded defect to 15 digits every run.

---

## Not checked, and why

- **`src/` behaviour beyond what a test's claim required.** The spectral
  luminosity fold (`spectral.jl` ~1000/~1103) is quoted in LEAD U18-2 as the
  mechanism behind a measured test-side gap and is flagged as a **cross-file seam
  for the auditor**; it was not audited as source.
- **The MPI axis.** Nothing in 2200-4400 exercises MPI, so there is nothing to
  report; the Phase 9 "MPI agreement" item is not covered by this region.
- **Float32 / precision-change coverage.** The region tests `BigFloat` promotion
  (in the 2084 testset's head, outside my lines) and dual numbers, but no Float32
  path; whether that is covered elsewhere in the file is outside my region.
- **Whether the example scripts assert anything beyond exit 0.** The testset at
  3356 asserts `success(p)` only; auditing the scripts themselves is `examples/`
  work, not test-file work.
- **The full suite was not run** (the auditor runs it, per the brief). Every number
  above comes from testsets executed in isolation.
