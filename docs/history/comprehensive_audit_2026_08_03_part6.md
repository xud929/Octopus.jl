# Comprehensive Audit — 2026-08-03, part 6

> ## Start here
>
> **This pass found more than the previous three combined, and most of it is not
> fixed.** Read §1 for the split between what was confirmed-and-fixed and what is
> confirmed-by-an-agent-but-not-yet-by-me.
>
> | read | why |
> |---|---|
> | **§1** | the ledger: two fixed, twelve recorded, and why the line falls there |
> | **§2** | S20 — a CUDA/CPU divergence of a **factor of 100** under a supported mode |
> | **§5** | the twelve recorded findings, each with its reproduction, for the next session to verify and fix |
> | **§6** | provenance and the agent hit rate — roughly 60%, which is why §5 is not presented as settled |

Sixth pass against [`docs/comprehensive_audit.md`](../comprehensive_audit.md),
covering `slicing.jl`, the CUDA slicing and Gaussian sequential paths,
`BeamObservers.jl`, `Knobs.jl` + `symbolic.jl`, `spectral.jl` and
`spectral_cuda.jl` — roughly **6,000 lines**, read by six sub-agents on disjoint
regions.

> **A note on this ledger's own history, because it was wrong twice.** The
> `spectral.jl` agent was interrupted; I recorded the file as uncovered and said
> so. It then resumed and completed. So `spectral.jl` **is** covered, and the
> intermediate claim that it was not is itself corrected here rather than edited
> away — the same rule this series applies to its technical conclusions.

## 1. Executive summary

| # | severity | area | state |
|---|---|---|---|
| S20 | **Major** | the CUDA spectral Dirichlet box ignored `allow_lost_particles`; CPU 1.589e-3 vs CUDA 1.592e-1 half-width — **a factor of 100** | **fixed, verified by me** |
| S19 | Minor | `_nonfinite_coordinate_error` reported "0 of N macroparticles have a non-finite coordinate" — asserting what its own scan had just disproved | **fixed, verified by me** |
| R1–R12 | Major → Minor | twelve further findings (§5) | **confirmed by an agent, NOT independently verified, NOT fixed** |

### Why the line falls there

Two findings were reproduced by me directly and fixed. The other eight are
recorded with their reproductions and left for the next session.

That is a deliberate stopping point, not an omission. This session's measured
agent hit rate is roughly **60%** (§6): of the claims agents have raised across
parts 4–6, several dissolved entirely on checking — one because the CPU had the
identical structure, one because the option it worried about is rejected on that
backend anyway. Fixing eight unverified findings in sequence, at the end of a
long session, would be exactly the failure mode the protocol's "confirm before
you modify" gate exists to prevent. §5 gives the next session everything needed
to verify each in minutes.

## 2. S20 — a factor of 100, under a documented supported mode

The spectral Dirichlet box is sized from **whole coordinate arrays**, not from
slice membership. The CPU knows this and says so (`spectral.jl`, `_masked_rms` /
`_masked_ext` docstring):

> "unlike the PIC meshes it is built from whole coordinate arrays rather than
> from slice membership — so the mask that slicing applies for free does not
> reach here and has to be explicit."

The CUDA re-implementation was written with unconditional reductions:

```julia
rms(v) = begin n = length(v); m = sum(v) / n; sqrt(sum(abs2, v .- m) / n) end
ext(v) = maximum(abs, v)
```

### Evidence

Four particles marked dead (`pz = NaN`) carrying **finite but far-out**
coordinates at `|x| = 1e-1`, under `allow_lost_particles()`:

| | half-width |
|---|---|
| CPU `_spectral_box` | 1.5894818318553923e-3 |
| CUDA `_cuda_spectral_box` | **1.5920521973915616e-1** |
| relative difference | **9.9e+01** |

Every slice pair then sees a different mesh, so every kick differs. The path is
*half*-masked, which is what makes it insidious: `_cuda_longitudinal_slices` does
drop the dead from `slices.indices`, so they never deposit and never get kicked.
Only the box is wrong.

A second consequence: a dead particle carrying `NaN` in `x` or `y` makes the box
non-finite and raises `_nonfinite_coordinate_error` — which that function's own
docstring says cannot happen under the flag, because "the reductions upstream of
every caller skip it". CPU proceeds; CUDA throws.

### Fixed

`_cuda_masked_rms` / `_cuda_masked_ext`, using the same `ifelse.` masking idiom
as `_cuda_live_z_stats` in `pic_cuda.jl` — a dead entry contributes the
reduction's neutral element, so a NaN it carries can never reach the accumulator.
Applied to both the plain and the drifted box.

Post-fix, measured: clean beams **0.000e+00**, with dead particles **1.364e-16**,
for both boxes. Fail-fast preserved and verified in both directions — a NaN in
`x` with the flag **off** still throws; the same NaN on a particle marked dead
with the flag **on** is masked out and the box is finite.

### Why it hid

The CPU lost-particle test covers `SpectralPoissonSolver`. The CUDA
lost-particle test covers only moments and slicing. The CPU/CUDA spectral parity
test never enters `allow_lost_particles`. Two supported features, each tested
alone, never tested together — the cross-product shape `docs/todo.md` names as
"the shape to look for", and the fourth time this series has found it.

## 3. S19 — a diagnostic that asserted what its own scan disproved

Called with entirely finite input, `_nonfinite_coordinate_error` threw:

> `0 of 3 macroparticles have a non-finite coordinate; first at index 0 with .`

An error asserting a fact it had just disproved, with an empty detail and a
nonsense index, sending the reader to the particle array when the fault is
upstream of it.

**The agent found this on the CUDA fused wavefront path. It is broader.** The
callers fire on a non-finite *derived* quantity, and a drifted position
`x + px·s` can overflow to `±Inf` from perfectly finite `x` and `px` when the
drift is large — so it is reachable on **CPU** too, for a completely different
reason than the one reported. The new message names both causes.

It also absorbs the agent's second confirmed finding — that the wavefront guard
can blame beam 1 for beam 2's moments, because the kick crosses beams. The
message now says the beam it names need not be the beam at fault. Restructuring
the wavefront check to attribute correctly would be a design change on a hot
path with no wrong physics behind it.

## 4. Areas checked and found sound

- **The symbolic differentiator is correct.** All 24 rules independently derived;
  68 finite-difference cases in the live package to ≤2.9e-11; cross-checked
  against Symbolics.jl's `expand_derivatives` on 12 expressions to ≤5e-15. The
  single most likely place for a silent wrong gradient — constant-exponent vs
  variable-exponent `^` — is correctly separated, including the constant-base
  case where the spurious `log(a)` term folds away. The five non-smooth
  operations (`sign`, `min`, `max`, 2-arg `log`, 2-arg `atan`) all refuse with a
  directed error rather than returning something wrong.
- **The Gaussian moment reductions use the safe form**, `offset = (active+1)÷2`,
  not the strict-halving form that part 5 showed drops 36 of 100 elements. Since
  `CUDALaunchConfig(threads=100)` genuinely produces a 100-thread moment block,
  that choice is load-bearing — and correct.
- **`slicing.jl` is clear of the `Core.Box` class** that once corrupted its
  default `:equal_area` boundaries: 0 boxes across all 40 methods, checked on
  lowered IR. Boundaries, weights, centers and index sets are **bit-identical at
  1, 4, 8 and 16 threads** across 12 configurations.
- **Every spectral CUDA transform derived from scratch** and matched: the
  odd/even extensions, both `rfft` sizings, the spectrum-index extraction, and
  both scale foldings; the DST/DCT equivalences are algebraic identities, not
  approximations.
- **No observer field is entirely unread** — every constructor-facing field of
  every observer type reaches a runtime consumer, with a `file:line` for each.
- **The spectral solve is mathematically correct, verified independently.** The
  agent derived the Dirichlet eigenfunction solution, the RODFT00/REDFT00
  normalisation factors and both field scales from scratch, then checked the
  solver against an explicit `O(Nx*Ny)` continuum mode sum it wrote itself — on a
  deliberately **anisotropic 13x21 grid**, agreeing to **2e-15 relative** on Phi,
  Ex and Ey for both `:grid` and `:grid_free`. Cross-checked against the audited
  PIC solver: per-particle correlation 0.9996 (px), 0.9996 (py), 0.9992 (pz).
  Sign included. This closes the largest unaudited block of mathematics in the
  repository.
- **The one `Core.Box` in `spectral.jl` is confirmed benign**, upholding part 1's
  judgement rather than merely repeating it: the closure only *reads* `luminosity`
  (through `typeof`), the write is outside the `do` block, and
  `_run_logical_workers` is `@sync`-joined. Verified end to end — bit-identical
  luminosity and coordinates across 6 repeats at 8 threads, and between 1 and 8
  threads. The latent hazard is now named: the natural refactor
  `luminosity += local_lum` *inside* the closure would reproduce the
  `_threaded_histogram` defect exactly, and no current test would catch it.
- **Lost-particle masking in the moment observers** is correct on both backends,
  including the ordering subtlety that the CUDA path must zero the dead *after*
  forming the product because dead coordinates are non-finite.

## 5. Recorded, not fixed — the next session's work

Each is agent-confirmed with a reproduction. **None has been independently
verified by me.** Verify first, then fix.

| # | severity | finding |
|---|---|---|
| **R1** | **Major** | **`:equal_count` slicing on CUDA is not equal-count when z has ties.** CPU builds indices from the sort permutation; CUDA computes boundaries only and re-assigns by comparison, so tied values all fall one side. Measured n=2000, ns=9: CPU counts `[222,222,222,222,223,…]` vs CUDA `[211,196,236,238,163,…]` — a **27% relative error in a slice weight**, and slice weights multiply `kbb` directly. The docstring promises "exact empirical equal-count slices". |
| **R2** | Moderate | **CPU `:equal_count` returns a `boundary` and an `indices` that contradict each other** — 244 of 2000 particles lie outside the `[lb,rb)` their own slice reports. Bounded by the interpolation clamp, but `boundary` is consumed as the slice extent by every PIC and spectral path. |
| **R3** | Moderate | **The Symbolics adapter can never activate.** `Symbolics` is in no section of `Project.toml`, so `import Symbolics` inside the module fails unconditionally and `_HAS_SYMBOLICS` is permanently `false` — measured on a machine where Symbolics **is** installed. The error message tells the user to install a package they already have. ~20 lines unreachable, two exports permanently dead, the round-trip test always takes the `else` branch. The adapter body itself is correct: 31/31 expressions round-trip when run where the import resolves. |
| **R4** | Moderate | **`@knob p::T` changes a knob's value with no epoch bump and no cache invalidation.** `_resolve_knob_type_locked!` converts the stored value, then the `rhs === nothing` branch returns without touching the epoch. Measured: `knob_value(:a)` reports the new `Float32` value while dependent `:b` and every compiled runtime keep the old one, and nothing recompiles. `set_knob!` gets this right; this path does not. |
| **R5** | Moderate | **`MomentObserver` truncates its output on every `execute!`.** It reopens with mode `"w"` on each call, so a run split across two `execute!` calls keeps only the last chunk — measured `[0.0, 2.0]` then `[4.0]`. Contradicts `Tasks.jl`'s documented "splitting a run across multiple `execute!` calls preserves schedules". Every other observer appends. |
| **R6** | Moderate | **`_scheduled_turns` plans on a turn *count* while `should_run` tests an *absolute* turn.** Any `start_turn ≠ 0`, or any second `execute!`, plans 0 records while the observer fires — measured `BoundsError` crash. Also mis-plans silently where the counts happen to overlap. |
| **R7** | Minor | **Zero-width z distribution disagrees three ways.** CPU `:equal_area`/`:equal_width` put everything in slice 1; CUDA puts it in slice `ns`; CPU `:equal_count` splits evenly. Same input, three answers. Reachable for a single-particle beam. The existing degenerate tests assert only that the total count is right, never *which* slice. |
| **R8** | Minor (perf) | **CUDA `:equal_area` is 10–20× slower than it needs to be** — a per-bin loop of full-length device broadcasts. Measured 53.4 ms vs 2.6 ms at n=1e6, ns=15. At the **default** `nslices=1` the histogram's only consumer is an empty loop, so all 3.8 ms per beam per collision is discarded work. |

| **R9** | Moderate | **Spectral has no dropped-charge accounting, unlike PIC.** Out-of-box source charge is silently absent, with no counter, no warning, no receipt — where `_pic_report_dropped` exists precisely because "dropped charge is a correctness event, not a tuning statistic". Measured: 3 of 6 sources outside the box gives a field **exactly 0.5x** the in-box field at every probe. *Framing correction to the agent's report:* that ratio is the in-box fraction, and since `kbb` normalises per particle it is physically **right** when the escapees are far away (they contribute ~0). It is wrong only for a particle just outside the wall, which the `1.05*emax` sizing is designed to prevent. So the live gap is the missing counter, not the normalisation. |
| **R10** | **Major (if reachable)** | **`method = :grid_free` ALIASES rather than drops.** A source at `x = 1.7L` produces exactly **-1x** the field of a source at `x = 0.3L` — the odd periodic extension mirrors it back inside with a sign flip. A silently wrong field, not a missing one. Reachability depends on whether the box can ever under-cover; verify against the sizing before scoring severity. |
| **R11** | Minor | **`field_precision` is reported `status=resolved` on CPU, which provably ignores it** (its docstring says "The CPU path always uses Float64"). The `supported_backends` machinery that would mark it `inactive_backend` exists and is used correctly by PIC one file over. All 13 spectral options carry the default `consumer=:solver_runtime`, so the schema self-check passes vacuously for this solver. |
| **R12** | Minor (perf) | **`_spectral_collide_transverse!` does `n1*n2` field solves where `n1+n2` suffice** — the source mesh is identical for every field slice `j` but is recomputed inside the `j` loop. Measured 0.77 ms (1 pair) to 30.0 ms (64 pairs); ~8x redundant at 8 slices. The longitudinal path genuinely cannot be hoisted. |

Lower-priority items also recorded in the agent reports and not repeated here: a
`consumer=` label with no referent, a docstring detached from its binding by a
blank line, `EveryNSteps`'s validation bypassable through the positional
constructor, and a `1.05·emax` box headroom that is insufficient below `Nx = 41`
(unreachable at production grids).

## 6. Provenance, and the agent hit rate

Six sub-agents read ~6,000 lines on disjoint regions, each given a *different*
hypothesis drawn from the five defect classes established in parts 1–5, plus the
known-good reference to compare against and a requirement that every claim carry
a `file:line`.

**Their output is a lead, not a finding, and this session has the numbers to
justify saying so.** Across parts 4–6, of the claims agents raised:

- several were confirmed and became real fixes (S18, S19, S20);
- several dissolved on checking — the "latent trap" that turned out to be
  identical on both backends by design; the missing dropped-particle accounting
  that cannot matter because the only under-covering estimator is rejected on
  that backend; a "wrong grid" concern that was safe by an invariant rather than
  by luck;
- one was *broader* than reported — S19 reaches the CPU for a reason the agent
  did not identify.

That last category is the argument for re-deriving rather than trusting: the
agent's own framing was too narrow, and taking it at face value would have
produced a CUDA-only fix for a CPU-reachable defect.

Everything in §2 and §3 was reproduced by me before any code changed. Everything
in §5 was not, and is labelled accordingly.

## 7. Handoff

### Next, in priority order

1. **Verify and fix R1** (`:equal_count` ties). Highest severity in §5, and slice
   weights feed `kbb` directly. Reproduction is in the table.
2. **R6 then R5** — both make `MomentObserver` wrong in ordinary chunked runs,
   which is a documented workflow.
3. **R3, R4** — the knob subsystem. R3 is a one-line `Project.toml` change plus a
   test that would have caught it.
4. **R2, R7, R8** — bounded or performance-only.
5. **Wave 2, still unread**: `gaussian_pic.jl` (850), `gaussian_pic_cuda.jl`
   (1,182), `Knowledge.jl` (885), `Tasks.jl` (759), `Registry.jl` (209),
   `BPMObserver.jl` (240) — ~3,900 lines.

### The technique that produced this pass

**Give each agent a different hypothesis, and the known-good reference.** The six
briefs named a specific failure mode each — tree-reduction orphaning, declared-
and-never-read, invariants broken between functions, degenerate-parameter
blindness, the symbolic derivative as unreviewed mathematics. The two that found
the most were the two whose hypothesis matched a defect class this codebase has
already produced.

**Then verify the crux yourself.** S20's factor of 100 was measured, not read.
