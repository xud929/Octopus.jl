# Comprehensive Audit — 2026-08-04, part 8

> ## Start here
>
> **This pass verified and fixed the head of part 7's queue.** Six findings were
> reproduced before any code changed — and for the first time in this series,
> **every claim taken up survived verification**: four exactly as stated, one
> broader than stated, and one whose shared-root-cause framing was wrong in a
> way that mattered to the fix.
>
> | read | why |
> |---|---|
> | **§2** | verdicts against part 7's claims, including the framing correction |
> | **§3** | the fixes, each with its negative control |
> | **§5** | two defects in this session's own probes, recorded per protocol |
> | **§6** | what remains open in the queue |

Eighth pass against [`docs/comprehensive_audit.md`](../comprehensive_audit.md).
No new reading: `src/` was fully covered by part 7, and this session is the
verify-and-fix phase that queue was written for.

## 1. Declared scope (Phase 0, recorded before work began)

Verify, then fix if confirmed: **T3** (the only undefined-behaviour item), the
`LineEntry` root-cause check against **T1/T4/T5**, then **K1**, then **G1**.
Depth: full reproduction of each claim before any edit; a behavioural
fingerprint before the first modification; a negative control for every
regression test. Deliberately not covered: T2, T6–T11, G2–G4, C1–C3, K2–K8,
and part 6's R2, R7–R12, the Symbolics package extension, and the
method-overwrite guard. Push access verified before starting (dry-run against
`github-dxu`).

## 2. Verification verdicts

| # | part 7 claimed | verdict |
|---|---|---|
| T3 | unchecked `@inbounds`/`CUDA.@atomic` write past the end of `counts`, reachable from a nested-vector line; kills reported `unattributed` | **CONFIRMED as stated.** `_aperture_specs` sized `counts` at 1 while the runtime walk bound ids 1 *and* 2; under `--check-bounds=yes` the bump is `BoundsError: attempt to access 1-element Vector{Int32} at index [2]`, under default flags it silently writes past the end; the summary reported the NESTED collimator's kill as `unattributed = 1` with a warning |
| T4 | the same nested vector zeroes aperture arc length | **CONFIRMED.** `_aperture_s_positions` gave `[1.0]` where `[3.5]` is correct, and dropped the nested aperture's entry entirely |
| T1 | the knob epoch never fires for a `BeamLine` task | **CONFIRMED as stated.** After `set_knob!`, the tuple twin moved `0.00035 → 0.0006` while the `BeamLine` task stayed `0.00035` and `knob_value` reported the new number. `set_knob!` bumps only the knob epoch (`Knobs.jl`), and with `knob_dependent = false` the cache gate short-circuits true forever |
| T5 | a `BeamLine` task declares no contracts and no analyses | **CONFIRMED.** `contracts=[] analyses=[]` against the tuple twin's `[ElementTrackingBackendConsistencyContract, PTCConsistencyContract]` / `[PlaceholderAnalysis]` |
| K1 | `RBendSpec` has no `ElementMeta`; `element_help` invents kind `:RBendSpec` and reports no contracts | **CONFIRMED.** All type-level queries missed the registry and returned confident emptiness; the instance resolved through `:sbend` exactly as the agent said |
| G1 | hard `MethodError` on a mixed-precision beam through the hybrid; plain PIC survives | **CONFIRMED, and broader than reported** — part 7 §4's fourth category. A **uniformly Float32** beam also threw, because the solver's own `kbb` is `Float64` by construction, so `promote_type(rep, rep, kbb)` ≠ `eltype(source.x)` for *every* non-Float64 rep. "Mixed precision" was never the condition |

**The framing correction that mattered.** Part 7 §2 presented T1/T3/T4/T5 as
one root cause — "`LineEntry` is not an `ElementSpec`, and five walkers handle
that inconsistently". Measured, it is **two mechanisms**: T3/T4 are
*nested-`AbstractVector`* blindness (`_append_runtime_line!` recurses into
vectors; the two aperture collectors did not — `LineEntry` never enters it),
and T1/T5 are *`LineEntry`* blindness (`_has_knob_parameters` and
`_collect_contracts`/`_collect_analyses` — vectors were already handled or
irrelevant there). One fix at the imagined single root would have closed two
findings and left two open. This is the "right, with the stated reason wrong"
category doing exactly what §4 said it does: the reason determines the fix.

## 3. Fixes, each verified before and after

All four T-items and both K1/G1 were fixed in this session. The behavioural
fingerprint (163 lines: aperture-line tracking, `BeamLine` tracking, a knob
task, a fused multi-element line, `element_help` for three kinds plus
`RBendSpec`, plain-PIC and hybrid collisions, the registry summary) is
**bit-identical** before and after, except the two intended K1 text changes.

**T3/T4 — `src/tasks/Tasks.jl`.** `_collect_aperture_specs!` and
`_collect_aperture_s!` gained the `AbstractVector` recursion that
`_append_runtime_line!` already had, with a comment naming the invariant.
`_bind_apertures` now asserts `id[] == length(record.counts)` at bind time —
if the walkers ever diverge again, the failure is a loud host-side error
naming the two walks, not an unchecked device write. Post-fix: `counts ==
[1, 1]`, both kills attributed, `unattributed = 0`, arc positions
`[1.0, 3.5]`; clean under `--check-bounds=yes`; **verified on CUDA too**
(RTX 4500 Ada), where the same task path previously fed the undersized vector
to `CUDA.@atomic`.

**T1 — `src/elements/beam_line.jl`.** `_has_knob_parameters(::LineEntry)`
checks the placement's spec *and* its overrides (either can hold a knob
expression); `_has_knob_parameters(::ElementSpec{:line})` covers a line kept
whole (a cryostat carrying its own state), whose composite compile resolves
its placements' knobs. A knob-free line still reports `false`, or every line
task would recompile every turn. Post-fix the `BeamLine` task tracks
`set_knob!` exactly as the tuple task does.

**T5 — `src/tasks/Tasks.jl`.** `_collect_contracts`/`_collect_analyses`
rewritten as one recursive walk (`_collect_declared!`) over tuples, vectors,
placements, and kept-whole lines. A `BeamLine` task now declares exactly what
its tuple twin declares, and a nested vector's contracts are seen too.

**K1 — `src/knowledge/Knowledge.jl` + `src/elements/lattice_magnets.jl`.**
`register_friendly_alias!(T, query)` maps an additional friendly constructor
type onto an existing `ElementMeta`; `RBendSpec` is registered onto `:sbend`,
which is what its constructor builds (parallel faces = `angle/2` added to each
of `e1`/`e2`, then `SBendSpec`). `element_help(RBendSpec)` now reports kind
`:sbend`, the PTC and backend-consistency contracts, and the full parameter
schema; the sbend `construction_help` gained one sentence stating the RBend
conversion. `validate_element_metadata()` passes; the registry snapshot is
unchanged (the alias registers no new spec).

**G1 — `src/tasks/strongstrong/gaussian_pic.jl`.** The two drifted-solve
helpers derived their scalar type from `eltype(source.x)` while the caller
allocates the profile buffers and `workspace.charge` in
`promote_type(rep1, rep2, kbb1, kbb2)` — and `_gpic_gaussian_profile!`'s
typed signature requires buffer and scalars to agree. They now derive it from
the buffer they were handed (`eltype(gxbuf)`), which is the workspace
convention the plain PIC already follows; the plain path survives Float32
beams only because its deposit helpers are generically typed. Post-fix all
four precision combinations pass on both the uncoupled and the coupled
(rotated-subtraction) branches; Float32 agrees with Float64 to ~6e-9 relative
(input precision), and the all-Float64 luminosity is bit-identical to the
fingerprint.

### Negative controls

Each new test was run against the pre-fix source (stashing only the fix under
test) and confirmed to fail there:

| test | on broken source | on fixed source |
|---|---|---|
| "Every walker over the line agrees…" (T1/T3/T4/T5) | **11 of 15 assertions fail** | 15/15 pass |
| K1 block in the PTC/metadata testset | **0 of 7 pass** | 7/7 pass |
| "GaussianPIC hybrid accepts non-Float64 beams" (G1) | **errors with the MethodError** | 4/4 pass |

## 4. Adjacent gaps observed, recorded, not fixed

- **An aperture inside a line kept whole is never bound to the loss record.**
  A stateful line compiles to a single composite runtime object; only
  `PhysicsEntry{<:Aperture}` entries are bound, so such an aperture takes the
  record-free kill path and its kills surface as `unattributed`. Both walkers
  miss it *consistently*, so there is no sizing mismatch and no UB — one
  severity class below T3. Same family as T5's kept-whole case, which IS now
  handled for contracts.
- **`_pic_solve_drifted_field_with_green_fft!` (plain PIC) still derives its
  scalar type from `eltype(source.x)`.** Harmless today — every helper it
  calls is generically typed, and all four precision cases pass — but it is
  the same pattern G1 grew from, one file over.

## 5. Two defects in this session's own probes

Recorded because part 6 §8.7 established the precedent, and both are the
class this series keeps finding in the library.

- **A closure swallowed the very BoundsError the probe existed to catch.** The
  first bounds-checked T3 run wrapped `execute!` in `try/catch` inside an
  `allow_lost_particles() do` block, with `err = e` in the catch. At script
  top level that assignment creates a *closure-local*, not the global — so the
  error was caught, discarded, and the run printed `dead = 1, unattributed =
  0`, which reads as "no OOB and no kill" — a wrong conclusion with plausible
  numbers. Caught only because the missing kill contradicted the unchecked
  run. The probe now threads the error through a `Ref`.
- **A keyword splat placed positionally** (`f(a=1, kw...)` instead of
  `f(; a=1, kw...)`) made the coupled-branch probe die in the constructor and
  nearly reported the coupled path as unreachable. The error message named the
  inner constructor, not the call-site mistake.

## 6. What remains open

> **Follow-up (2026-08-04, same day):**
> [part 9](comprehensive_audit_2026_08_04_part9.md) settled everything below
> except R8 and R12, which remain open as performance-only items. The list is
> kept as written.

- From part 7: **T2, T6–T11** (Tasks.jl), **G2–G4** (gaussian_pic), **C1–C3**
  (gaussian_pic_cuda), **K2–K8** (Knowledge/Registry — including the two
  validator gaps in the todo table, which K1's fix does not close).
- From part 6 §5: **R2, R7–R12**, the Symbolics package extension, and the
  method-overwrite guard (§8.7).
- Nothing regressed: the full suite passed at `--threads=4` **with the CUDA
  half active** (RTX 4500 Ada) on the final tree, after the fingerprint diff
  above.

## 7. The running tally on agent claims

Parts 4–7 measured ~60% survival. This session's six-for-six looks like a
counterexample; it is not. The queue was *ordered by verifiability* — these
six were taken first precisely because each carried a mechanical reproduction,
and even so, one arrived with the wrong root-cause framing and one narrower
than the truth. The two claims that needed correction were correctable only by
measurement, which is the same lesson at a better hit rate.
