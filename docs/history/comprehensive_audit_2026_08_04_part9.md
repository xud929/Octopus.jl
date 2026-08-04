# Comprehensive Audit — 2026-08-04, part 9

> ## Start here
>
> **This pass worked everything left in the queue except two performance
> items.** Twenty-four findings from parts 6 and 7 were verified and settled:
> twenty-two fixed (several with corrections to the recorded claim), one
> resolved by documenting its actual contract, one rejected-then-upgraded when
> this session's own instrumentation found a reachable case the original
> analysis missed.
>
> | read | why |
> |---|---|
> | **§2** | the verdicts, including the four claims that needed correcting |
> | **§4** | R9/R10 — the pre-collision box assumption, and the 83% silent charge loss the new tripwire caught |
> | **§6** | this session's own errors, including one that destroyed uncommitted work |
> | **§7** | what remains open: R8 and R12, both performance-only |

Ninth pass against [`docs/comprehensive_audit.md`](../comprehensive_audit.md),
continuing [part 8](comprehensive_audit_2026_08_04_part8.md). Declared scope:
T6 and T2 first, then T7–T11, G2–G4, C1–C3, K2–K8, R2, R7–R12, the Symbolics
package extension, and the method-overwrite guard. Every claim reproduced
before its fix; behavioural fingerprint bit-identical across all three fix
batches; negative controls run by stashing the fixes and asserting the new
tests fail.

## 1. The two headline items

**T6 — a crashed `execute!` (CONFIRMED as stated, both halves).** A failure at
turn 3 of 5 left the loss file unwritten — `MISSING` with kills already
recorded and a log path given — and the documented retry (the stored turn
deliberately does not advance) appended duplicate turn labels:
`[0,1,2,0,1,2]`. Fixed on both halves without touching the documented turn
semantics: `execute!` flushes the loss summary, file, and warnings on the
failure path before rethrowing; and BPM observers discard readings at or
beyond the upcoming window when preparing — a no-op for ordinary chunking,
idempotence for retries, and the correct behaviour for an explicit
`start_turn` rewind, which duplicated labels too. The TSV mirror is rewritten
from memory when anything is dropped, and the noise-occurrence counter forgets
the failed pass so a retry redraws identical noise.

**T2 — task reuse across backends (CONFIRMED as stated, both directions
measured).** CPU→CUDA reuse died compiling the kernel (host `counts` in device
arguments); CUDA→CPU died with `MethodError: _aperture_bump!(::CuArray, …)`.
The `fits` test compared shape only, against its own docstring's "shape or
backend". `_loss_record_matches_rep` now mirrors the constructor's placement
decision, plus the slots eltype. Both directions verified clean post-fix, with
the record visibly reallocated per backend.

## 2. Verdicts on the rest, with corrections kept visible

| # | verdict | disposition |
|---|---|---|
| T7 | **CONFIRMED** — one throwing finalizer stranded both the remaining task-level observer and every line observer | both finalizer loops now finish their list and rethrow the first error; the `finally` nests so line observers run even when task-level finalization throws |
| T8 | **CONFIRMED** — the BPM noise read the live global RNG, so a mid-run `set_global_rng!` retroactively changed a reading | the draw now uses the `TrackingContext` snapshot, exactly as stochastic tracking does; the `turn`-only method keeps its interactive globals-snapshot behaviour |
| T9 | **CONFIRMED** — a BPM read twice in one turn drew identical noise | occurrence index added to the counter key, riding in the free particle slot; occurrence 0 reproduces the pre-existing stream bit for bit |
| T10 | **CONFIRMED** — 9.3 µs at `first_turn=0` vs **29.52 ms at 1e8**, matching the recorded number | the planner enumerates from the first schedule point ≥ the window start; 0.05 ms at 1e8, zero mismatches against the enumerate-and-filter oracle over a 4,800-point parameter grid |
| T11 | **CONFIRMED** — `rng_id` absent from the BPM schema | added, always reported (its value is auto-assigned, so a default comparison would lie) |
| G2 | **CONFIRMED, broader** — bit-parity fails even with `neutralize=false` (~1.4e-13 relative), so the neutralize-quantity mismatch was never the whole story | the docstring now states measured rounding-level agreement and names both causes (reduction order; deposited-total vs particle-count normalisation) |
| G3 | **CONFIRMED as stated** — coupled subtraction WORKS on the default CUDA route and throws on the other two, so the main docstring was right and the constructor comment + configuration_report ("CPU path only") were the stale texts | both corrected, the old claim kept in the comment |
| G4 | **CONFIRMED — exactly six**: `interaction_grid`, non-linear `slice_interpolation`, `grid_extent=:sigma` (both backends); `cuda_async/cuda_batch_fft/cuda_wavefront_fft = false` (CUDA) | the "forwarded unchanged" docstring now says which six are rejected at collide time and why |
| C1 | **CONFIRMED asymmetry** (reachability not established) — three CUDA uncoupled neutralisation sites divided unguarded where the CPU and the CUDA coupled branch both guard | the same `> 0` guard on all three sites |
| C2 | **CONFIRMED** — `choose = (a,b) -> a[1] ? a : b` is non-commutative under a `mapreduce` CUDA.jl documents as commutative | anchor is now the lexicographic minimum of the coordinate tuples: commutative, associative, deterministic; any in-slice anchor is mathematically valid, so the change is roundoff-sized |
| C3 | **CONFIRMED** — timing records on the indexed route only; the sequential route used the green cache and never reported it | coarse phase timing and the cache report on all three routes; verified: records now appear on each |
| K2 | **resolved transitively** — the three thin named-strength constructors build **bit-identical** runtimes to the PTC-validated `ThinMultipoleSpec` spellings (all six equivalences verified), which is what justifies their `PTCConsistencyContract` | equivalence pinned in the suite; the claim stands on the shared runtime, not on per-constructor PTC cases |
| K3 | **CONFIRMED** — the tracking-method check asked whether a list's elements were in itself | validator now checks declarations against the architectural roots AND compiles every example to a declared runtime type; the injected liar that used to validate clean now fails on three independent counts |
| K4 | **CONFIRMED** — `runtime_type` (singular) stored, never read post-construction | consistency check: it must appear in the runtime map |
| K5 | **CONFIRMED** — `push!(required_contracts(…), Int64)` corrupted the registry while validation still passed | the four list-returning query pairs return copies |
| K6 | **CONFIRMED** — `nameof(nothing)` crashed snapshot generation for permitted metadata | reported as "(no friendly constructor)" instead |
| K7 | **CONFIRMED** — three hand-written sections under a "derived from the type graph" claim | the docstring now names them |
| K8 | **CONFIRMED** — `compile_runtime(::ElementSpec{:line}, args...)` discarded an explicit method request | rejected with direction to set `tracking_method` on placements |
| R2 | **CONFIRMED, mechanism pinned** — 238/2000 boundary violations with quantized z, **zero with continuous z**: rank-based membership cannot be an interval property under ties, and every violating particle sits exactly ON its reported boundary | the contract is now documented on the slicing docstring and pinned by tests; no code change, deliberately — R1 chose rank semantics and made both backends agree on it |
| R7 | **CONFIRMED** — degenerate z: slice 1 on the CPU equal-width/area paths, slice `ns` on CUDA and on every boundary-search path (a backend divergence AND a CPU-internal inconsistency) | one convention — slice 1 — on both backends and all methods |
| R11 | **CONFIRMED** — `field_precision` reported `resolved` on CPU | one `supported_backends=(CUDABackend,)` keyword; now `inactive_backend` on CPU, `resolved` on CUDA |
| R3 (completion) | the load-mode asymmetry part 6 diagnosed | **the package extension exists**: `[weakdeps]` + `ext/OctopusSymbolicsExt.jl`, registration in `__init__` (a top-level registration is silently discarded with the precompile process — measured, §6), script mode activates at include; both modes verified end to end, and the suite's round-trip is now unconditional |
| §8.7 guard | — | a testset forces `Base.compilecache` and asserts no overwrite message: measured on this Julia, a runtime include is SILENT about overwrites and the compile driver can exit 0 while the worker reports the collision, so the guard greps the message rather than trusting either signal. Verified: 2 hits on an injected collision, 0 clean |

## 3. R9 — the tripwire, and what it immediately caught

Part 6 recorded the missing spectral dropped-charge counter with the framing
correction "the live gap is the counter, not the normalisation". The counter
is now a mass-deficit tripwire after both grid deposits (CIC weights sum to
one per in-box particle, so the grid total's deficit IS the clipped fraction).

**Verifying it found a reachable case the queue did not record.** The
Dirichlet box is sized ONCE per collision from pre-collision coordinates —
which cover every drifted deposit by construction (1.05× the masked extremum
plus the worst-case drift bound; derived, not assumed). But deposits happen
after earlier slice pairs' kicks. On a strong-kick configuration
(`max|px|`: 1e-5 → 0.69 in one collide), later pairs' drifted sources land
far outside the box and **83% of a slice's charge was silently discarded** —
before the tripwire, with no signal of any kind. At production kick scales
the growth is orders of magnitude inside the headroom and the tripwire is
silent.

## 4. R10 — rejected as recorded, then upgraded by §3

The recorded worry was aliasing for a source outside the box. For
pre-collision coordinates that is unreachable — the box covers them by
construction, and this session derived rather than assumed it. That would
have closed R10 as "mechanism real, internal-API only". **The R9 measurement
above reopened it**: the same intra-collision kick growth reaches
`:grid_free`, where an out-of-box source does not clip — the odd periodic
extension mirrors it back inside at **exactly −1×**, silently. A guard now
warns on the mode-sum path, verified firing on the strong-kick configuration
and silent on a mild one. This is the fourth time in the series a claim's
verification changed its scope in the middle of the check.

## 5. Negative controls

| tests | on pre-fix source | on fixed source |
|---|---|---|
| T6/T2 probe | 6 pass / 2 fail / 1 error (missing file, duplicate labels, KernelError) | 14/14 |
| T7–T11 probe | finalizers stranded, live-reseed match, identical noise, 29.53 ms, `rng_id` absent | all five inverted |
| K probe | registry corrupted while the validator passed; snapshot `MethodError`; silent method acceptance; the liar validated clean | all four inverted |
| C3 probe | timing records on one route of three | records on all three |
| overwrite guard | 2 collision messages on an injected duplicate | 0 |

## 6. This session's own errors, recorded per protocol

- **A careless `git checkout src/tasks/Tasks.jl` destroyed the uncommitted
  T6/T2/T7 fixes** while cleaning up a negative-control injection. Recovered
  by re-applying the three edits from context and re-running the 14/14 probe.
  The lesson is the one the fingerprint discipline already encodes: revert by
  removing exactly what was added (the injection had a grep-able marker), not
  by resetting a file that carries unrelated state.
- **Two probes were mangled by shell quoting** (`'\n'` terminating a
  single-quoted `-e` string), one of which made the overwrite-guard probe
  silently test nothing. Probes now go through script files.
- **The R9 tripwire was first placed in only one of the two grid deposit
  functions** — the one the default path never calls. Caught because the
  verification expected a warning and got none.
- **The extension's adapter registration was first written at the module's
  top level and was silently discarded with the precompile process**
  (`active: false` after `using Symbolics`). Moved to `__init__`; the failure
  mode is now documented in the extension file.

## 7. What remains open

> **Follow-up (2026-08-04, same day): R8 and R12 are now closed too.** Both
> measured before and after, both bit-identical.
>
> **R8**: the per-bin device broadcasts were replaced with one atomic
> histogram kernel whose bin membership is corrected against the exact
> per-bin edge expressions the masks compared with — ties, the closed last
> bin, and the rounding-dropped extremes land identically. Measured at
> n=1e6: **57.8 → 3.2 ms at ns=15** (18×), and the default `nslices=1` now
> skips the histogram whose only consumer was an empty loop: **3.9 →
> 0.32 ms**. Slice counts, boundaries, weights and centers bit-identical
> across five configurations including quantized ties; a per-bin-mask oracle
> pins the kernel in the suite.
>
> **R12**: `_spectral_field_grid!` split into a source-only solve and a
> mesh eval; the transverse path pre-solves every source once (positions are
> never mutated there, so both directions' solves are valid up front) and the
> kick loops evaluate stored meshes in the exact order they used to solve in.
> Full transverse collides captured pre/post at 4 threads, ns=8:
> **kicks and luminosity bit-identical**. Solve count per collision:
> `2·n1·n2 → n1+n2`. Wall time with luminosity scheduled off, n=20k,
> grid 64: **75.5 → 39.0 ms at ns=16** — the removed ~36 ms matches the 480
> deleted solves; the remainder is the per-pair eval/kick work the pair
> structure requires. With the default per-pair luminosity on, the gain is
> smaller (86 → 56 ms) because those pair-dependent overlap deposits — which
> cannot be hoisted without changing numbers — now dominate; recorded, not
> chased. `:grid_free` keeps per-pair mode sums, noted in the code.

The list as it stood before that follow-up:

- **R8** — the CUDA `:equal_area` histogram costs 10–20× more than needed,
  and at the default `nslices=1` its only consumer is an empty loop. Pure
  performance; needs the benchmark discipline this session had no room for.
- **R12** — `_spectral_collide_transverse!` does `n1·n2` field solves where
  `n1+n2` suffice (the source mesh is identical for every field slice).
  Same category.
- From part 7, unchanged: nothing — T1–T11, G1–G4, C1–C3, K1–K8 are all now
  settled.
- The CUDA spectral deposit has no tripwire (the CPU one is new); the
  strong-kick reachability applies there too.
- The `fits`/backend interplay for a line kept whole (aperture inside a
  composite runtime is never bound to a loss record) — recorded in part 8 §4,
  still open.
