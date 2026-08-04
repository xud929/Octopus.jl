# Comprehensive Audit — 2026-08-03, part 4

> ## Start here
>
> **This pass found nothing, and that is the result.** `pic_cuda.jl`'s host-side
> orchestration was audited against a specific hypothesis — that it had inherited
> more of the CPU's defects the way it inherited S14 — and the hypothesis failed.
>
> | read | why |
> |---|---|
> | **§1** | the hypothesis, and why an empty findings list here is evidence rather than absence |
> | **§3** | what was checked and found sound — this is the substance |
> | **§4** | three claims this pass made and then had to withdraw or correct, including one that nearly became a false finding |
> | **§5** | remaining risks, and §6 the handoff |
> | **§7.3** | **if you are the next session, start here** — the field-solver extension was begun and stopped mid-region, with an exact resume line and the specific question to carry in |
>
> §2 is the coverage ledger. Read it before trusting any coverage claim here.

Fourth pass against [`docs/comprehensive_audit.md`](../comprehensive_audit.md),
resuming from [part 3](comprehensive_audit_2026_08_03_part3.md) §9, which ranked
`pic_cuda.jl` next and — unusually — handed it a *specific question* rather than a
general one.

## 1. Executive summary

**Zero confirmed defects.** No source behaviour changed. One docstring added.

Part 3's S14 showed `_cuda_pic_slice_pair_cached_prep!` inheriting a defect
*verbatim* from the CPU, with the parity test blind to it because both backends
broke the same invariant identically. The governing question here was therefore
not "is this code correct in isolation" but:

> **Which invariants does `pic_cuda.jl` re-derive rather than share, and does each
> re-derivation still hold?**

Anything computed independently on the two backends is where parity is strong (a
divergence shows up immediately). Anything *shared and wrong*, or *copied and
wrong the same way*, is where parity is blind. That is the map this pass followed.

Both classes came back clean, and the checks were built to fail loudly:

- The re-derived device functions were compared against their CPU twins
  **numerically**, over 200,000 randomised samples, not by eye.
- The `ρ = 1` blind spot that produced *two* defects in `pic_cpu.jl` (part 3
  §10.6) was tested at aspect ratios 1:1, 11:1 and 25:1 against an **analytic**
  reference, not against the CPU.
- The `Core.Box` class was swept over lowered code, closing a `docs/todo.md` item
  that recorded the CUDA paths as never having been checked.

An empty findings list from a genuine review is a successful audit, and
manufacturing Minor findings to appear thorough is itself a defect in the audit
(Phase 17). §4 records the two things this pass nearly filed and shouldn't have.

## 2. Declared scope and coverage ledger

Declared before reading in depth. The file is 5,807 lines and 168 definitions;
claiming a full line-by-line pass would be the failure mode Phase 0 exists to
prevent, so the scope was differentiated by depth and its boundary stated.

### Read in full, line by line — 2,260 lines

| region | contents |
|---|---|
| l. 1–1502 | entry points, both collide drivers, the workspace/cache/timing structs, reclaim, slice gather/scatter, and **all six interaction routes**: async pair, batched-FFT pair, wavefront batched-FFT, fused Gaussian wavefront, indexed wavefront, node-indexed wavefront |
| l. 1502–2260 | `prepare_interaction`, the indexed-wavefront bounds prepare, `finish_interaction_indexed`, node grid build/prebuild/lookup, node interaction, all five kick launchers, the indexed node and pair kick kernels, the slice-pair Green cache, every grid helper, expand/realign, both `solve_field` entry points |

### Read in part, in pursuit of specific questions

- l. 2285–2317 (`solve_drifted_field_with_green_fft`), l. 3472–3700 (the whole
  luminosity block), l. 3873–3890 (`atan_ratio`, `kernel_integral`),
  l. 4263–4300 (CIC/TSC weights), l. 4558–4594 and 4709–4737 (kick kernels).

### Three mechanical sweeps — the whole file, 5,807 lines

1. **Mirrored-invariant sweep** — which CPU helpers are shared vs re-derived.
2. **`ρ = 1` blind-spot sweep** — per part 3 §10.6.
3. **`Core.Box` census** over lowered code — 288 methods, extending part 1 §3.

### Not covered, and why

Device kernels beyond those listed (l. 3700–5040, ~1,340 lines) — part 1 §9a
assessed the kernel layer as lower risk and part 3's evidence pointed at host-side
orchestration. The Gaussian sequential path and CUDA slicing (l. 5040–5810, ~770)
— a distinct subsystem that belongs with the unread `slicing.jl`. The field
solvers / wavefront workspaces / Green stacks (l. 2252–3470, ~1,220) — named in
Phase 0 as the first thing to extend to if the sweeps came back quiet. **They
did, so that is now the recommended next step rather than a deferral.**

### Honest total

~2,600 of 5,807 lines (45%) read line by line, plus three whole-file sweeps.
Across parts 1–4, roughly **50% of `src/`** has been read line by line.

## 3. Areas checked and found sound

The substance of the pass.

### 3.1 The re-derived function pairs

The device cannot call host helpers, so `cic_weights`, `tsc_weights`,
`kernel_integral`, `atan_ratio` and `interpolate_kick` are duplicated. Compared
numerically over 200,000 randomised samples:

| pair | worst difference |
|---|---|
| CIC weights + base index | **0.000e+00** (bit-identical) |
| `kernel_integral` | **0.000e+00** (bit-identical) |
| TSC weights + base index | 1.110e-16 |

The TSC difference is deliberate and undocumented: CUDA computes the third weight
as `w3 = 1 − w1 − w2`, an exact partition of unity, where the CPU uses the closed
form. Both were derived by hand in part 3 §2.3 and both are correct.

**The S6 copied-bug hypothesis failed.** Part 2's S6 was an `UndefVarError: PI`
in the CPU `_pic_atan_ratio`'s on-axis branch. Its CUDA twin never carried it:
`atan_ratio(±1, 0)` returns `±π/2` on both, `(0,0)` returns 0 on both.

### 3.2 The `ρ = 1` blind spot does not recur

Part 3 §10.6's lesson — a check that cannot distinguish anything at `hx = hy` has
now produced two defects in `pic_cpu.jl` — was applied here. Four candidate sites
(the three `klum/(hx·hy)` luminosity scales and the Green normalisation
`−0.5/(hx·hy)`) are all per-axis. Tested against the **closed-form Gaussian
overlap** rather than against the CPU:

| aspect | analytic | CPU | CUDA | CUDA rel. error |
|---|---|---|---|---|
| 1:1 | 8.793091e+06 | 8.778681e+06 | 8.778681e+06 | −1.639e-03 |
| 11:1 | 8.771281e+07 | 8.756631e+07 | 8.756631e+07 | −1.670e-03 |
| 25:1 | 5.495682e+07 | 5.486676e+07 | 5.486676e+07 | −1.639e-03 |

Flat to the analytic value independent of aspect ratio, and CPU/CUDA identical to
printed precision.

### 3.3 The wavefront invariant, checked rather than assumed

This is the load-bearing argument for the whole CUDA scheme and it holds:

- **Within a wavefront batch no two pairs share a slice index.** So the
  progressively-updated states the CPU uses and the pre-batch states CUDA uses
  are *equivalent*, not merely close; and the `idx1`/`idx2` writes of different
  pairs cannot collide. Parity is therefore meaningful rather than coincidental.
- **All field solves for a batch complete before any kick launches**, so both
  directions read the un-kicked opposing slice — matching the CPU, where the
  source is an unmutated extract and the field a copy.
- **Luminosity is consumed before the kicks on every route.** Not a theoretical
  concern: the comment at l. 868–871 records the batched-FFT path being
  "measurably wrong (1.8e-4 relative)" before its fetch was moved.

### 3.4 The kick kernels reproduce the CPU term for term

All three (plain, node-indexed, pair-indexed) implement:
drift in with **old** momenta → `pz −= ¼(px²+py²)` with **old** → interpolate at
the drifted position → kick → drift out with **new** momenta →
`pz += ¼(px²+py²)` with **new**. Checked against `_pic_interaction!` and
`_pic_interaction_node!` line by line. Aliased in/out arrays are safe: each
thread reads and writes only its own element, read before write.

The node path additionally selects `gL = nc[j]`, `gR = nc[j+1]` and solves `phiZ`
on **gL's** mesh, which is what the theory note requires — `φ_L − φ_R` is a small
difference of large numbers whose discretisation error cancels only within one
mesh.

### 3.5 Concurrency

- **`Core.Box` census: 288 methods defined in `pic_cuda.jl`, 0 boxed.** Closes the
  `docs/todo.md` item recording the CUDA paths as unchecked for the part 1 §3
  class. Done on lowered code — a text sweep gave six false positives and missed
  a real case in part 1.
- **Four concurrent field streams are safe**: each gets its own
  `workspace.charges[k]`, and `phi`/`Ex`/`Ey`/FFT scratch are freshly allocated
  per call. No shared mutable state.
- **`_cuda_pic_add_time!`'s non-atomic accumulate is safe**: no yield point
  between `getproperty` and `setproperty!`, and the tasks are `@async`
  (cooperative, single-threaded), not `@spawn`.

### 3.6 Buffer reuse without re-zeroing

The fused Gaussian route reuses `lum` and `partials` across batches without
clearing them. Both are safe because every read is bounded — `lum[1:lum_offset]`
where each segment writes a contiguous, fully-covered range, and `partials` read
only up to `block_counts[c]`. Checked rather than assumed, because a stale-buffer
sum is exactly the kind of bug that survives a parity test if both backends do it.

### 3.7 Grid invariants are shared, not re-derived

All three CUDA grid-building sites call the shared `_pic_interaction_grids`, so
alignment, `grid_quantize` and `min_transverse_extent` are inherited. Part 3's S16
class (an option silently dropped by an alternative sizing path) does not recur
here.

## 4. Corrections to this audit's own analysis

Three, and the first two are the ones worth reading.

### 4.1 The "latent trap" was overstated — **withdrawn**

I reported that `_cuda_pic_interaction_wavefront_node_indexed!` (l. 1352–1364)
rebuilds the node cache *lazily* on a miss, which is precisely what both prebuild
docstrings forbid and which is recorded as having made CPU/CUDA disagree by
3.8e-5; and I framed it as a CUDA-specific latent trap.

**That framing is wrong.** The CPU has the identical structure:
`_pic_node_grid!` (`pic_cpu.jl:794`) → `_pic_build_node_grids!` with the same
`isempty(cache) || return cache` guard (l. 691), and `_pic_collide!` prebuilds
unconditionally (l. 58–60). The lazy call is a deliberate no-op guard on **both**
backends. It is not CUDA-specific and warrants no change — "fixing" it would mean
altering two identical structures for zero behavioural effect. It survives only as
a remaining risk (§5).

### 4.2 A near-miss: the beam-swap that wasn't

`_cuda_pic_launch_kick_pair_indexed!` orders its two argument groups by **opposite
conventions** — the `rep`/`idx` groups name the *recipient* beam, the plane groups
name the *producing* beam. So the first beam group pairs with the *second* plane
group. Reading the call site alone, this looks like the two beams' fields are
swapped, which would be a major physics error.

It is correct. Establishing that required tracing to
`_cuda_pic_kick_pair_indexed_kernel!` 2,700 lines away, where the pairing is
actually made (`idx2 ← phi12*`, `idx1 ← phi21*`), and confirming both wavefront
solvers fill planes identically.

This came within one step of being filed as a Major finding on the *production*
route. It is recorded because the near-miss is the useful part: the code was
right and the reading was wrong, and the only thing that would have caught a
premature report is the discipline of confirming before writing. A docstring now
states the pairing at the launcher.

### 4.3 `slices.weight` is not a dead field

I reported `weight` as a dead field. It is dead only in `pic_cpu.jl`'s
`param1`/`param2` **tuples** (built at l. 71–73, read nowhere). The underlying
`slices.weight` is live — the fused Gaussian wavefront route reads
`slices2.weight[j]` and `slices1.weight[i]` at `pic_cuda.jl:1147` and `1158`. The
dead thing is the tuple copy, which is cosmetic and left alone.

## 5. Remaining risks

- **Node-cache prebuild and lazy fallback are consistent by caller discipline
  only** (§4.1). Both backends prebuild unconditionally under `:node`, which is
  what makes the lazy path a no-op. A future caller that skips the prebuild would
  silently reintroduce a measured, documented defect. Symmetric across backends,
  so it is a design property rather than a bug.
- **`green_cache` is vestigial on the CUDA path.** Both producers return `nothing`
  unconditionally, so it is `nothing` everywhere while being threaded through ~20
  functions, and `_cuda_pic_cached_interaction_grids` is a pure pass-through. Dead
  parameter, live caching elsewhere (the slice-pair cache in the workspace).
- **Dead but correct code**: `_cuda_pic_wavefront_luminosity_batched` (65 lines) is
  reachable only through `_cuda_pic_batched_luminosity_enabled()`, a hardcoded
  `false` — a complete alternative implementation of a headline observable that no
  test has ever run. Executed directly for this audit: it agrees with the live
  path to 1.6e-15 at both round and 11:1. Left in place.
- **A float-association mismatch inside CUDA.** `_cuda_pic_prepare_interaction`
  computes the field drift as `x + px*half*(z−c)` while the CPU *and the CUDA kick
  kernel* both use `x + (0.5*(z−c))*px`. Multiplication is not associative, so the
  bounds are computed ~1 ulp from the drift actually applied. Harmless against a
  1.5-cell margin, but the two CUDA sites disagree with each other while both
  mirror the same CPU line.
- **The unread half.** l. 2252–3470 (field solvers, wavefront workspaces, Green
  stack builders) and the device kernels are not covered by anything but the three
  sweeps.

## 6. Handoff

### Done, do not redo

| area | state |
|---|---|
| `pic_cuda.jl` l. 1–2260 | **read in full**; zero defects |
| The six interaction routes | all read; the wavefront invariant verified rather than assumed |
| Re-derived CPU/CUDA function pairs | verified numerically equivalent, 200k samples |
| `Core.Box` class on CUDA | **swept, 288 methods, clean** — closes the `todo.md` item |
| The `ρ = 1` blind spot | tested against an analytic reference at three aspect ratios |
| CUDA luminosity | verified against the closed-form Gaussian overlap |
| The field-solver extension, **partially** | see §7 — ~400 of 1,220 lines, with an exact resume point |

### Next, in priority order

1. **`src/tasks/strongstrong/pic_cuda.jl` l. 3038–3430 — the quadratic routes.**
   *(This item was started; see §7 for what is already covered and §7.3 for the
   exact resume point and the question to carry in.)* Originally scoped as
   l. 2252–3470 — the field solvers,
   wavefront workspaces and Green stack builders. Phase 0 named this as the
   extension target if the sweeps came back quiet, and they did. It is also where
   the batched FFT plane bookkeeping lives, which §4.2 shows is the most
   error-prone part of this file to read.
2. `src/tasks/BeamObservers.jl` (1,446) — only l. 700–1030 read (part 2).
3. `src/knobs/Knobs.jl` (896) + `symbolic.jl` (285) — `symbolic.jl` was declared in
   part 2's scope and never reached.
4. `spectral.jl` (1,045) + `spectral_cuda.jl` (760) — untouched by any audit.

### Techniques that mattered

- **Test the shared thing against an external reference, not against the other
  backend.** Parity cannot see a defect both backends share — that is what S14
  was. Every check here that could be anchored to an analytic result (the Gaussian
  overlap, the closed-form kernels) was.
- **Randomised comparison beats reading for duplicated functions.** 200,000
  samples through both the CPU and CUDA weight functions took minutes and is worth
  more than any amount of side-by-side reading.
- **Confirm before filing.** §4.2 came within one step of a false Major finding on
  the production route.
- **A clean sweep is a deliverable.** The `Core.Box` census closing a standing
  `todo.md` item is worth as much as a defect would have been, and it is only
  worth anything because it is recorded with its method count.

---

# 7. Extension in progress — the field solvers (l. 2252–3470)

§6 named this region as the next target. It was **started, not finished**, and
this section exists so the next session resumes at a line number rather than
re-deriving where the boundary fell.

**Nothing found. ~400 of ~1,220 lines.** No source changes.

## 7.1 The hypothesis being tested

§4.2 identified the batched-FFT **plane bookkeeping** as the most error-prone
thing in this file to read: which plane index holds which field, and whether the
deposit, the Green stack, the per-plane cell size and the kick all agree on it.

It is a good hypothesis because it is the one class a parity test is weak
against. A plane mix-up that is *symmetric* between the two backends would agree
at 1e-13 while being wrong — exactly S14's shape. And unlike S14 there is no
shared helper to anchor on: each backend lays out its planes independently.

## 7.2 Covered, and what makes it right

| lines | function | verdict |
|---|---|---|
| 2252–2337 | `solve_field_with_green_fft`, `solve_drifted_…` | sound (read in the part-4 pass) |
| 2337–2392 | `solve_pair_fields_batched_fft!` | sound |
| 2392–2427 | `allocate_wavefront_workspace` | sound |
| 2428–2483 | `wavefront_workspace!` | sound |
| 2484–2495 | `reserve_wavefront_workspaces!` | sound |
| 2496–2546 | `wavefront_node_workspace!` | sound |
| 2547–2625 | `solve_wavefront_fields_node_indexed!` | sound |
| 2858–2952 | `copy_green_spectral_stack!`, `build_wavefront_green_fft!`, `green_plane_params!` | sound |

**The node route is the model to compare the rest against.** It documents its
layout and then drives both the deposit and the Green copy from the *same* tuple,
so the two cannot drift apart:

    +1 dir1 L  sL1 gL1    +4 dir2 L  sL2 gL2
    +2 dir1 R  sR1 gR1    +5 dir2 R  sR2 gR2
    +3 dir1 Z  sR1 gL1    +6 dir2 Z  sR2 gL2

- Deposit `specs` (l. 2583–2590) and Green-stack copy (l. 2609–2611) carry
  identical `(plane, mesh)` pairings.
- `hx_host[plane]` comes from the mesh that plane was *actually* deposited on
  (l. 2596–2597), so the field derivative uses the matching cell size per plane.
- Plane +3 (Z) sits on **gL**, same as +1 (L) — the physics requirement, since
  `φ_L − φ_Z` is a small difference of large numbers whose discretisation error
  cancels only within one mesh.
- The kick call (l. 1416–1428) reads `+1,+1,+1,+2,+2,+3` as
  `phiL, ExL, EyL, ExR, EyR, phiZ` — matching the layout exactly.

**The design decision that removes the risk**, per the workspace docstring
(l. 2496–2509): node mode allocates **one Green per plane** and duplicates gL
into the L and Z slots, so the spectral multiply is a 1:1 elementwise product
with no mapping to get wrong. Where the mapping *is* non-uniform — the 4-plane
route, 4 charge planes over 2 Greens — the caller passes the correct Green
explicitly per plane (l. 2855–2859) rather than deriving it arithmetically.

**Guarded, not assumed**: `wavefront_workspace!` hard-validates
`nplanes % 4 == 0` and the node one `% 6 == 0`. A 6-plane request against the
4-plane allocator throws rather than silently mis-sizing `npairs = nplanes ÷ 4`.
That was the first suspicion of this stretch and it is explicitly defended.

**S14/S17 cross-check**: the `:lattice` branch of `build_wavefront_green_fft!`
(l. 2914–2931) calls `_pic_green_lattice!` per plane on host grids arriving
either straight from `_pic_interaction_grids` or through the realigned
`_cuda_pic_slice_pair_cached_prep!`. Both are aligned, which is why part 3's new
integrality guard does not fire here; the `:lattice` testset exercises both.

## 7.3 Resume here

Unread, in the order a next session should take them:

| lines | function | why it matters |
|---|---|---|
| **3038–3430** | `copy_green_spectral_stack_quadratic!`, the two quadratic solvers, the two quadratic interaction routes, `apply_indexed_quadratic_kick!` + kernel + launcher | **Start here.** This is `slice_interpolation = :quadratic`, and it is the one layout that has *not* been checked against the discipline in §7.2 |
| 2743–2858 | `solve_wavefront_fields_indexed_batched_fft!` | the production route's solver body; only its plane-fill loop has been seen, via grep |
| 2625–2743 | tail of the node solve, `solve_wavefront_fields_batched_fft!` | same, plane-fill loop seen only via grep |
| 2952–3038 | `apply_green_plane!`, the three `deposit_drifted_*_plane*` helpers, `multiply_spectral_perplane_kernel!` | the primitives all of the above call |
| 3430–3470 | `green_fft`, `build_green_fft` | small |

### The specific question to carry into the quadratic routes

Quadratic uses **6 planes per pair** (L/M/R per direction) and borrows the
**node** workspace — which allocates one Green per plane. But unlike node mode,
all three planes of a quadratic direction share **one** `source_grid`: the
docstring in `pic_cpu.jl` justifies this by noting the drifted coordinate
`x + px·s` is affine in `s`, so the sL/sR bounding box already contains the
midpoint plane and no resizing is needed.

So the duplication factor is **3, not 2**, and the borrowed workspace was sized
for a different grouping. The questions are:

1. Does `copy_green_spectral_stack_quadratic!` (l. 3038) duplicate each
   direction's Green into all three of its slots?
2. Are `wf.hx[plane]`/`hy[plane]` filled for all six planes, given all three of a
   direction share one mesh?
3. Does the kick (`apply_indexed_quadratic_kick!`, l. 3355) read planes in the
   order the solver filled them?

Compare against §7.2's node layout, which is the known-good pattern.

### What would make this cheap to settle

The CPU has an independent quadratic implementation
(`_pic_interpolate_kick_quadratic`, verified by hand in part 3 §2.6: basis
`2t²−3t+1, 4t−4t², 2t²−t` summing to 1, derivative weights summing to zero). The
parity test covers `slice_interpolation = :quadratic`, so a plane mix-up that is
*asymmetric* between backends is already excluded. What remains to check by
reading is a mix-up that is symmetric — which, per §7.1, is the only kind that
survives parity, and is precisely what S14 was.
