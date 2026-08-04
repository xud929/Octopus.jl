# Comprehensive Audit — 2026-08-03, part 5

> ## Start here
>
> | read | why |
> |---|---|
> | **§3** | S18, the one confirmed defect: a public CUDA tuning surface that is completely inert on the bare `collide!` path — 0 launch receipts against 12 through a task |
> | **§4** | the tree-reduction orphaning analysis, and why the invariant that saves it is held by an unasserted literal in a different function from its two guards |
> | **§5** | areas checked and found sound — the bulk, including a byte-identical three-way kernel comparison |
> | **§6** | agent claims rejected, and one correction to part 1's record |
>
> §2 is the coverage ledger, and it is the section to read sceptically: most of
> this region was read by **sub-agents**, not by me, and it says which.

Fifth pass against [`docs/comprehensive_audit.md`](../comprehensive_audit.md),
extending part 4 to the CUDA **device kernels**, `pic_cuda.jl` l. 3470–5040.

## 1. Executive summary

| # | severity | area | state |
|---|---|---|---|
| S18 | Moderate | `CUDAPICLaunchConfig` is **silently inert** on a bare `collide!` — every launch family falls back to a fixed 256 and the device max-threads validation never runs. Both the PIC and the composed GaussianPIC routes. | fixed (now warns), verified |
| V1 | verification gap | the luminosity tree reduction's power-of-two guard — two `ispow2` validations, **neither exercised by any test** | fixed, verified |

S18 is audit part 2's **S1 all over again**: a public performance-tuning surface
that does nothing, on a documented public API. S1's evidence was "0 receipts →
56"; this one measures **0 receipts on the bare path against 12 through a task**,
with the identical solver and configuration.

The difference is instructive. S1 was a dispatch bug — an `isa` test that missed a
composing type. S18 is not a bug in any function: `_with_solver_execution_configuration`
correctly installs the scoped configuration, and its only caller is the task
path. The configuration is inert because of **where the resolution lives**, and
nothing on the `collide!` path was obliged to notice.

## 2. Declared scope and coverage ledger

### Region: `pic_cuda.jl` l. 3470–5040 (~1,340 lines), the device kernels

Read by **four sub-agents** on disjoint regions, each given a *different*
hypothesis rather than a generic brief, plus the known-good reference to compare
against and a requirement that every claim carry a `file:line`:

| agent region | hypothesis it was given |
|---|---|
| field-derivative kernels (3 variants) | must reproduce the CPU `_pic_field!` in all four stencil cases, both axes, including signs and the fourth-order fallback rings |
| bounds reduction + gather/scatter | tree-reduction orphaning; neutral elements; whether the block **cap** drops particles |
| interpolation + kick appliers | the `Kz` unweighted-difference asymmetry, and old-vs-new momenta in the two `0.25(px²+py²)` brackets |
| luminosity + spectral multiplies | the power-of-two tree reduction, and whether its validation covers **every** path |

### Read by me directly

The power-of-two reachability question (§4), which is the crux of the fourth
brief, was settled by me independently — by experiment, before the agent
reported. The S18 confirmation (§3) is likewise my own measurement, not an
agent's claim.

### Provenance, stated plainly

Most of this region was **not** read by me line by line. The Absolute Rules
require the ledger to make coverage claims checkable, so: the four agent reports
are the evidence for §5, each carries `file:line` citations, and every item any
agent flagged was re-derived by me before being accepted or rejected (§6 records
two rejections). Where a conclusion rests on measurement rather than on reading,
§3 and §4 say so.

### Honest total

`pic_cuda.jl` is now covered to l. 5040 — **~87%**. Remaining: the Gaussian
sequential path and CUDA slicing, l. 5040–5810 (~770), which belong with the
still-unread `slicing.jl`.

## 3. S18 — a tuning surface that is inert on one of its two paths

`CUDAPICLaunchConfig` is documented as "Optional CUDA-only PIC launch overrides.
`nothing` inherits the thread count from `CUDAExecutionPolicy`." Nothing in that
docstring hints that the object is inert unless routed through a task.

`_cuda_pic_threads` (`interface.jl`) has three exits:

```julia
config = _ACTIVE_CUDA_PIC_LAUNCH_CONFIG[]
config isa ResolvedCUDAPICLaunchConfig || return 256      # <- the third exit
```

The scoped value is installed by `_with_solver_execution_configuration`, whose
**only caller is the `StrongStrongTask` path**. A bare
`collide!(solver, beam1, beam2, CUDABackend)` never enters it.

### Evidence

Identical solver carrying `CUDAPICLaunchConfig(kick_threads=64,
deposition_threads=64, field_threads=64)`, counting `:cuda_pic_launch` receipts:

| path | receipts | threads seen |
|---|---|---|
| bare `collide!` | **0** | — configuration never reached the device |
| via `StrongStrongTask` | **12** | {64, 128} |

Two consequences, not one: the user's overrides are discarded for **all seven
families**, and `_resolve_cuda_pic_configuration`'s device
`MAX_THREADS_PER_BLOCK` validation is skipped along with them.

### Fixed

The path cannot simply honour the configuration — resolution needs a
`ResolvedCUDAExecutionPolicy` to inherit from, and a bare `collide!` has no
policy at all. Inventing a default would be a design change, not an audit fix. So
it is made **loud** instead: `_warn_inactive_pic_launch_config` fires exactly when
a configuration exists and cannot be installed, and records an
`:inactive_path` execution receipt — mirroring the `:inactive_backend` receipt
`_with_solver_execution_configuration` already emits for the reverse case.

Wired into both CUDA routes. The GaussianPIC one matters: the predicate goes
through `_pic_launch_solver`, which is precisely the dispatch fix part 2's S1
introduced so the composing type is not missed. A test asserts the hybrid warns,
so S1's shape cannot return here.

## 4. The tree reduction, and an invariant held by an unasserted literal

`_cuda_pic_luminosity_overlap_partials_kernel!` reduces with the strict-halving
form:

```julia
step = CUDA.blockDim().x ÷ 2
while step >= 1
    if tid <= step; shared[tid] += shared[tid + step]; end
    CUDA.sync_threads(); step ÷= 2
end
```

Each stage covers indices `1 … 2·step`, which equals the live range only while
that range is even. Whenever `step` is odd, `step ÷= 2` truncates and index
`step` — already holding a partial sum — is never read again.

Worked at `blockDim = 100`, sequence `50, 25, 12, 6, 3, 1`: the `step=12` stage
orphans `g[25]`, and `step=1` orphans `s[3]` (eight groups). The final sum
carries **64 of 100 elements**; luminosity comes out low by a data-dependent
factor near 0.64, with no error, no NaN and no bounds violation.

### Is it reachable? Measured, exhaustively — no

| path | `:luminosity` threads |
|---|---|
| bare `collide!`, no configuration | 256 (pow2) |
| policy threads 32 / 64 / 128 / 256 / 512 / 1024 | inherited unchanged, all pow2 |
| policy threads 96 / 192 / 320 / 100 / 224 | **rejected at resolution** |
| policy 96 + explicit `luminosity_threads=64` | 64 — the override rescues it |

Two guards do the work: the `CUDAPICLaunchConfig` constructor (`ispow2(lum)`) and
`_resolve_cuda_pic_configuration` (`ispow2(resolved.luminosity)`). No
non-power-of-two value reaches the kernel on any path.

### V1 — but neither guard was tested

A repo-wide grep for `luminosity_threads`, `ispow2` or "power of two" in
`test/runtests.jl` returned **nothing**. Both validations could have been deleted
and the suite would have stayed green, while the consequence is a silently wrong
luminosity — the number a beam-beam code is judged on. That is part 1's "checks
that exist and are never executed", guarding a headline observable.

**Fixed** with a test asserting the constructor rejection (host-side, no GPU
needed), the inherited-policy rejection, the override rescue, and that the
fallback is a power of two.

**One residual risk, recorded not fixed.** On the bare path the invariant holds
only because the literal `256` happens to be a power of two — and that literal
lives in a different function from both guards, with nothing tying them together.
Changing it to 192 or 768 (both plausible occupancy tunings, both ≤ 1024, both
passing every other constraint in sight) would silently break the reduction. The
robust fix is to make the reduction size-agnostic, in the style of the moment
reduction elsewhere in the same file which uses `offset = (active+1)÷2` and drops
nothing at any block size. That is a change to working code with no confirmed
defect behind it, so it is left as a recommendation.

## 5. Areas checked and found sound

- **The three field-derivative kernels are textually one kernel.** After
  normalising the element-type alias and the plane subscript, the three stencil
  blocks are **byte-identical** (verified by `diff`, 22 lines each, zero
  differences). All four CPU cases — interior 2nd, interior 4th, first-ring
  fallback, boundary one-sided — match term for term in both axes, with the
  negative-gradient sign consistent in every branch.
  - The CPU's explicit `nx >= 5` / `ny >= 5` gate has no CUDA counterpart, but
    the range test `j >= 3 && j <= ny-2` is **self-guarding** and selects the same
    branch at every size including the unreachable `ny = 4`. Not a defect.
  - `c4` is bit-identical despite different construction (`T(1)/T(12)` vs
    `typeof(hy)(1/12)`): 1/12's repeating mantissa never produces a
    round-to-nearest tie, so the double rounding is harmless.
- **The bounds reduction's block cap drops nothing.** `blocks = min(cld(n,
  threads), block_cap)` looks like truncation but the kernel is a grid-stride
  loop bounded by `length(idx)` with `stride = gridDim·blockDim` computed from
  the *actual* launched grid, so every element is visited exactly once. The
  complementary half holds too: the partials array is fully re-initialised each
  launch, and slots for blocks that never launched hold ±Inf.
- **Neutral elements are ±Inf, never 0.0.** Checked on every path. A `0.0`
  neutral in a min/max reduction would silently clamp the bounding box to include
  the origin — a real defect, and it does not occur.
- **The block reduce does not require a power of two**, only `blockDim % 32 == 0`:
  it pads the cross-warp stage with `lane <= nwarps ? shared[row,lane] :
  neutral[row]`, so 3 or 5 warps reduce correctly. Its thread counts (256 and 64)
  are hardcoded and deliberately bypass the configurable path.
- **`Kz` is the unweighted `phiL − phiR` difference** in both stencils on both
  backends — the asymmetry most likely to be transcribed wrongly, transcribed
  correctly.
- **The drift/kick/drift sequence** matches the CPU term for term including the
  critical old-vs-new momentum split in the two `0.25(px²+py²)` brackets, in all
  five kick kernels.
- **Node mode uses the correct mesh per plane**: L on gL, R on gR, and the
  longitudinal pair `phiL`/`phiZ` both on gL.
- **Gather/scatter is an exact inverse permutation**, and the mask compaction's
  *inclusive* `cumsum` is the right choice — an exclusive scan is where the
  off-by-one would be.
- **All four spectral-multiply kernels** map planes to Greens correctly; the
  ragged tail is handled by zero-filling before the barrier rather than an early
  `return`, which would have deadlocked it.
- **The wavefront luminosity kernel excludes the guard row/column**, matching the
  CPU's `for j in 1:ny, i in 1:nx` over an `(nx+1, ny+1)` array.

## 6. Claims rejected, and a correction to part 1

Agent reports are leads, not findings. Three items were dismissed after
re-derivation:

- **"The CUDA path has no dropped-particle accounting."** True as stated, cannot
  matter: `_require_cuda_pic_options` rejects every `grid_extent` but `:extrema`
  on CUDA, and `:extrema` covers every particle by construction.
- **"`hx` comes from `source_grid` while `phi` lives on `field_grid`."** A real
  observation with the wrong conclusion — it is safe by an *invariant*, not by
  luck, and that invariant is now tested (part 4 §8.1).
- **Several "latent fragility" notes** — a kernel without a grid-stride loop, a
  missing `n == 0` guard, dead `phi` parameters. All correct observations, all
  unreachable today, none warranting a change to working code.

### Correction to part 1's record

Part 1 states that the luminosity kernel "is fed by `_cuda_pic_threads(:luminosity)`,
and `interface.jl:112` and `:185` validate that family with `ispow2` at both
construction and inheritance resolution."

That is **incomplete**: it names two of the three exits from `_cuda_pic_threads`
and omits the fallback `return 256`, which neither guard covers. The conclusion
part 1 drew is still correct — no bad value reaches the kernel — but for a reason
it did not state, and the omitted exit is exactly where S18 lives. Recorded here
rather than edited into part 1, per the rule that a correction sits beside the
original.

## 7. Handoff

### Next

1. **`pic_cuda.jl` l. 5040–5810** — the Gaussian sequential path and CUDA
   slicing, the last ~13% of the file. Take it together with **`slicing.jl`
   (704)**, which is unread and is the CPU counterpart.
2. `BeamObservers.jl` (1,446) — only l. 700–1030 read (part 2).
3. `Knobs.jl` (896) + `symbolic.jl` (285) — declared in part 2's scope, never
   reached.
4. `spectral.jl` (1,045) + `spectral_cuda.jl` (760) — untouched by any audit.

### Recommendation carried forward

Make the luminosity overlap reduction size-agnostic (§4). It removes a live
constraint rather than documenting one, and the pattern already exists in this
file.

### What worked here

- **Give each agent a different hypothesis, not a generic brief.** The four
  briefs named the specific failure mode, the known-good reference, and demanded
  `file:line`. The one that found S18 was the one told to ask "does the
  validation cover *every* path?" rather than "check this region".
- **Settle the crux yourself.** The power-of-two reachability and the S18
  receipt count were both measured independently before the relevant agent
  reported. Agent output then corroborated rather than being trusted.
- **Count receipts, not lines.** S1 and S18 were both found the same way: ask
  what the device actually *did*, not what the configuration said it should do.
