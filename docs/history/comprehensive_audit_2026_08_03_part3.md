# Comprehensive Audit — 2026-08-03, part 3

> ## Start here
>
> **Do not read this front to back**, and do not read parts 1 or 2 front to back
> either. This pass covers exactly one file, `src/tasks/strongstrong/pic_cpu.jl`.
>
> | read | why |
> |---|---|
> | **§9** | the handoff: what is now covered and what is next |
> | **§1** and **§10** | the four defects. §10 is a same-day follow-up that closed the one open question §9 left, and found the largest accuracy defect of the pass doing it |
> | **§7** and **§10.2** | the wrong turns — three hypotheses this pass raised and its own measurements killed or corrected |
>
> §2 is the coverage ledger. §6 is the areas checked and found sound, which is
> most of the file and is the point of the exercise.
>
> If you read only one paragraph, read **§10.6**: the same blind spot — a check
> that cannot distinguish anything at `ρ = 1` — has now produced two separate
> defects in this one file.

A third pass against the protocol in
[`docs/comprehensive_audit.md`](../comprehensive_audit.md), resuming from
[part 2](comprehensive_audit_2026_08_03_part2.md) §14, whose priority list ranks
`pic_cpu.jl` first: it is the CPU reference every parity contract validates the
CUDA paths against, so if it is wrong the contracts agree on the wrong answer.

**That is not a hypothetical. It is what happened.** The largest finding here
(S14) is a Green function that both backends computed identically and both
computed for a source displaced by four tenths of a cell, with the CPU/CUDA
parity test passing at 1e-13 throughout.

**Four** confirmed defects, all fixed — three in the pass proper and a fourth
(§10) found by closing the one question the handoff left open. Three audit
hypotheses raised and then refuted or corrected by measurement, recorded in §7
and §10.2 rather than deleted.

## 1. Executive summary

| # | severity | area | state |
|---|---|---|---|
| S14 | **Moderate** | the Green cache's grid expansion destroys the integer-cell alignment `green_type = :lattice` is tabulated by; `_pic_green_lattice!` rounded silently, giving the field of a source displaced by 0.400 cells. Both backends, so parity agreed. | fixed, verified |
| S15 | Moderate | `_PICCPUWorkspace.dropped` was incremented and **read by nothing in the repository**, while its own comment said "Never silent", `grid_extent`'s metadata promised "dropped and counted", and `validation/README.md` said the count "must stay at zero" | fixed, verified |
| S16 | Minor | `grid_extent` is accepted and **bit-identically ignored** under `interaction_grid ∈ {:node, :source_slice}` | fixed (now rejects), verified |
| S17 | **Moderate** | the lattice Green function's periodic box is sized in *index* units, so at high aspect ratio it is physically far too flat; `:lattice` measured **10.3x worse** than the default kernel at the production aspect ratio, defeating the option's only stated purpose. Found by closing §9's open question — see **§10** | fixed, verified |
| P1 | performance | `_pic_field!`'s `Ey` pass walked a column-major array in row-major order — 42.8 µs → 3.0 µs at grid 128, bit-identical | fixed, measured |

**The pattern worth taking away.** Part 1's rule was "audit for checks that exist
and are never executed". Part 2's was "audit for values that are declared and
never read" — S15 and S16 are both squarely that, so the rule is still paying.

S14 is a third one, and it is the sharpest: **audit for invariants that one
function establishes and another quietly breaks.** `_pic_interaction_grids`
carefully aligns the two grids and says so; `_pic_expand_grid_by`, twenty lines
away, changes the cell size and undoes it. Neither function is wrong on its own.
Nothing that tests either of them in isolation can see it, and the thing built to
compare the two backends cannot see it either, because both backends break the
invariant the same way. What finds it is asking *what does this consumer assume,
and who guarantees it?* — `_pic_green_lattice!` assumed integer separation, the
comment above it named the function that guarantees it, and that function's
output no longer reaches it unmodified.

## 2. Declared scope and coverage ledger

Declared before reading anything in depth, per Phase 0. Scope was set by the
human and by the part 2 §14 handoff.

### Read in full, line by line — 1,732 lines

| file | lines | note |
|---|---|---|
| `src/tasks/strongstrong/pic_cpu.jl` | 1,732 (1,715 declared) | the whole declared scope |

### Read in part, in pursuit of specific questions

- `interface.jl` — the `PICPoissonSolver` struct and constructor validation
  (l. 1057–1180), the workspace and cache structs (l. 475–543),
  `_pic_luminosity_grid` / `_pic_luminosity_deposit_method` /
  `_pic_compute_luminosity` (l. 1207–1211, 1950–1975), the `grid_extent` option
  metadata (l. 1268–1291).
- `pic_cuda.jl` l. 2100–2245 — `_cuda_pic_slice_pair_cached_prep!` and the
  expansion helpers, because the CPU defect had to be checked for a mirror.
- `gaussian_pic.jl` l. 630–680 — it routes through `_pic_slice_pair_green!`, so
  S14 reached it too.
- `contracts/Contracts.jl` l. 2000–2090, 2294–2485 — the solver-option contract's
  probe/alternative tables and its main loop, which S16's fix made unrunnable.
- `validation/pic_gaussian_field_validation.jl`, `pic_grid_extent_stability.jl` —
  to establish what they actually score, which is how it became clear the Green
  cache is never in the loop when the kernel is measured.

### Deliberately not covered, and why

`pic_cuda.jl` bulk (5,807), `gaussian_pic_cuda.jl` (1,154), `spectral*.jl`
(1,805), `slicing.jl` (704), `gaussian_pic.jl` bulk — not this pass's declared
file. `interface.jl`, `Contracts.jl` and `strong_beam.jl` were read in full in
part 2 and were not re-read.

### Equations independently derived

1. **The integrated Green kernel.** `_pic_kernel_integral(x,y) =
   (ln r² − 3)xy + x² atan(y/x) + y² atan(x/y)` is the double antiderivative of
   `ln(x²+y²)`. Derived by hand: `∂F/∂x = y ln r² − 2y + 2x·atan(y/x)`, and
   `∂²F/∂x∂y = ln r² + 2y²/r² − 2 + 2x²/r² = ln r²`. The four-corner difference
   times `−1/(2 h_x h_y)` is therefore the cell average of `−ln r`. **Correct.**
   Also checked the one thing that derivation does not: `F` is *continuous*
   across `x = 0`, because the `x²` prefactor kills the `±π/2` jump in
   `atan(y/x)` — without which the four-corner difference of a cell straddling
   the axis would be wrong. It does.
2. **The lattice kernel normalization.** `∇²(−ln r) = −2πδ` and the five-point
   symbol is `−κ/h_x²` with `κ = (2−2cos t_x) + ρ²(2−2cos t_y)`, `ρ = h_x/h_y`,
   so `Ĝ = 2πρ/κ`. That is exactly `scale = 2pi*rho` over `ghat = 1/kap`,
   inverted with `ifft` (which carries the `1/N` the lattice sum needs).
   **Correct.**
3. **TSC weights.** For `δ = u − nearest`, `W(∓1) = ½(½∓δ)²`, `W(0) = ¾ − δ²`.
   Both branches of `_pic_tsc_weights` expand to exactly that, including the
   `f ≥ ½` branch where `δ = −(1−f)`. **Correct.**
4. **`_pic_align_grid_origins` does what it claims.** New separation is
   `d/h − (f₂−f₁)`, and `d/h = integer + (f₂−f₁)`, so the result is an exact
   integer (`:integrated`, `:lattice`) or exactly a half cell (`:standard`).
   **Correct** — which is what makes S14 a broken invariant rather than a wrong
   formula.
5. **The luminosity overlap**, verified against the closed-form Gaussian result
   `1/(2π√(σ₁ₓ²+σ₂ₓ²)√(σ₁ᵧ²+σ₂ᵧ²))` — see §5.
6. **Slice interpolation weights.** `zL = (rb − z)/(rb − lb)` from
   `_slice_interpolation_parameters`, which is 1 at `lb` and 0 at `rb`, matching
   `sL = ½(c_source − lb)`. The quadratic basis `2t²−3t+1`, `4t−4t²`, `2t²−t`
   sums to 1 and its `z`-derivative weights `3−4t`, `8t−4`, `1−4t` sum to zero,
   so the gauge constant in `φ` cancels. **Correct**, and both match the
   docstring's stated forms.

## 3. S14 — an invariant established by one function and destroyed by another

`_pic_interaction_grids` (`pic_cpu.jl:964-965`, and `955-956` under
`grid_quantize`) ends by calling `_pic_align_grid_origins`, which puts the source
and field grid origins an exact integer number of cells apart. The comment above
the lattice kernel says so explicitly (`pic_cpu.jl:1408-1412`):

> The table is indexed by INTEGER lattice separation, which is legitimate because
> `_pic_align_grid_origins` puts the source and field origins an exact integer
> number of cells apart for every `green_type` except `:standard`.

`_pic_slice_pair_green!` then expands both grids by `1 + slice_pair_green_growth`
(`pic_cpu.jl:988-989`) before building the Green function. `_pic_expand_grid_by`
scales `width` with the node count `nx` fixed, so the **cell size** grows by the
same factor while the origin separation does not. An exact `k`-cell separation
becomes `k/(1+growth)`.

### Evidence

Separation between the two origins, one representative slice pair, grid 64:

| `green_type` | growth | before expansion | after expansion |
|---|---|---|---|
| `:integrated` | 0.00 | 22.000000 (\|frac\| 3.6e-15) | 22.000000 |
| `:integrated` | 0.25 | 22.000000 | **17.600000 (\|frac\| 0.400)** |
| `:lattice` | 0.25 | 22.000000 | **17.600000 (\|frac\| 0.400)** |
| `:standard` | 0.25 | 21.500000 (a deliberate half cell) | **17.200000** |

`_pic_green_lattice!` (`pic_cpu.jl:1482-1483`) then did
`dx = round(Int, (field_x0 - source_x0) / hx)` — **rounding silently**. The
function already threw for a separation outside the tabulated range, with the
message "this indicates unaligned interaction grids", so it intended to catch
exactly this; it checked the wrong property.

The consequence is not a small error in the kernel value. It is the kernel of a
**displaced source**. Measured directly: one macroparticle at an exact source
node, apparent position located from the zero crossing of `Ex` on the field grid:

| grid pair | true source x | apparent x | offset |
|---|---|---|---|
| aligned (`green_cache = :none`) | −2.125000e−05 | −2.125000e−05 | **+0.0000 cells** |
| expanded (`green_cache = :slice_pair`, the default) | −2.010417e−05 | −2.468750e−05 | **−0.4000 cells** |

−0.4000 is exactly the rounding residual. Both backends do the same expansion
(`pic_cuda.jl:2123-2124`), so `test/runtests.jl`'s `:lattice` CPU/CUDA parity
check passed at `< 1e-13` on the displaced field.

### Why nothing caught it

- The `:lattice` testset (`test/runtests.jl:6166`) checks the *table* against
  `−ln r` (which is aligned by construction, separation 0), then checks
  end-to-end only that the result is finite, that it *differs* from
  `:integrated`, and that luminosity agrees to `rtol=1e-3`. A 0.4-cell field
  displacement passes all three.
- `validation/pic_gaussian_field_validation.jl` is the only place the kernel is
  scored against an analytic reference, and it calls `_pic_solve_field`
  (`pic_cpu.jl:1081`), which builds the Green function directly and **never
  touches the slice-pair cache**. The cache is out of the loop precisely where
  accuracy is measured.
- `SolverOptionEffectivenessContract` proves `green_type` reaches a consumer. It
  says nothing about whether the consumer is right — which part 2 §14 predicted
  in as many words.

### Fixed

`_pic_realign_expanded_grids` (`pic_cpu.jl`), called from `_pic_slice_pair_green!`
and from the CUDA mirror site, re-applies `_pic_align_grid_origins` with the
expanded cell size. `:integrated` is **deliberately excluded**: its kernel is
evaluated at real coordinates and does not depend on the alignment at all, so
re-aligning it would move the default mesh and change results that carry no
defect. `_pic_green_lattice!` now rejects a fractional separation instead of
rounding it.

Post-fix separations: `:lattice` 17.600000 → 17.000000 (residual 0.000e+00),
`:standard` restored to a half cell.

### What the fix does and does not buy

Honest accounting, because two attempts to show a physics improvement failed to
isolate one:

- The **displacement is gone**, which is measured directly and is not in doubt.
- Scored against the exact Bassetti–Erskine kick on a fixed grid at grid 128
  with the 11:1 production beams, the median relative field error moved
  3.097e−2 → 3.026e−2, a factor of **1.02**. The residual in that configuration
  was 0.2 cells, not 0.4, and the lattice kernel's own systematic error at that
  aspect ratio is an order of magnitude larger than the displacement it was
  masking.
- End to end at grid 64 against a grid-512 reference, the change is **not
  separable** from the grid-64 discretization error (§7.2).

So: a real defect, directly demonstrated, in a kernel that is documented
EXPERIMENTAL and explicitly not recommended for production. Fixing it is
justified by the invariant, not by a demonstrated change in a physics result, and
that is stated here rather than dressed up.

## 4. S15 — a counter written by one line and read by none, under a "Never silent" comment

`_PICCPUWorkspace.dropped` (`interface.jl:505-508`) counts particles that fell
outside the interaction mesh and were dropped by the zero-weight branch. Its
comment ends:

> non-zero means a robust estimator under-covered and the field lost charge.
> Never silent.

It was silent. A census over the lowered code of every method in the module found
`dropped` mentioned in **exactly one method** — `_pic_interaction!`
(`pic_cpu.jl:425`), the writer:

```
=== is _PICCPUWorkspace.dropped ever READ? ===
  methods mentioning `dropped`: 1
    _pic_interaction! @ src/tasks/strongstrong/pic_cpu.jl:425
```

Three separate documents promised it was observable:

- the field comment above, "Never silent";
- `interface.jl:1273`, `grid_extent`'s option metadata: "out-of-range particles
  are dropped **and counted**";
- `validation/README.md:531`: "`dropped` must stay at zero for a production
  setting".

`validation/pic_grid_extent_stability.jl` does print a `dropped` column, which is
what makes this look covered — but it recomputes its own from `_pic_axis_extent`
(l. 109–110) and never reads the runtime counter.

Measured consequence, `grid_extent = :sigma, grid_extent_sigma = 2.0`, 3000
particles per beam: **389 particles dropped**, luminosity 0.1% off, and no signal
anywhere. At `grid_extent_sigma = 1.5`: **1842 dropped**, silently.

### Fixed

`_pic_report_dropped` warns from `_pic_collide!` whenever the count is non-zero,
and the counter is reset per collision so the number means "this collision".
Dropped charge is a correctness event, not a tuning statistic, so it warns rather
than printing only under the diagnostics flag. It is silent at zero, which is
every run under the default `grid_extent = :extrema`.

The count was also **moved** to after the Green cache resolves the final grid,
and is now taken against `field_grid` rather than the estimator box. The old
placement over-reported: the mesh carries 1.5 cells of margin beyond the
estimator box, so a particle sitting in that margin was counted as dropped while
being interpolated perfectly well.

## 5. S16 — `grid_extent` accepted and bit-identically ignored under two of three mesh modes

`grid_extent` is consumed by `_pic_axis_extent`, which only the per-slice-pair
sizing path in `_pic_interaction!` calls. `:source_slice` sizes its mesh from
`_pic_union_bounds` and `:node` from `_pic_build_node_grids!` — both take plain
`min`/`max` over their own particle sets and never consult the estimator.

Controlled test, identical beams, comparing full coordinate arrays:

| `interaction_grid` | `:extrema` vs `:sigma` | vs `:sigma`, `grid_extent_sigma = 2.0` |
|---|---|---|
| `:slice_pair` | differs (option read) | differs (option read) |
| `:source_slice` | **BIT-IDENTICAL** | **BIT-IDENTICAL** |
| `:node` | **BIT-IDENTICAL** | **BIT-IDENTICAL** |

The control matters: `grid_quantize` and `min_transverse_extent` were checked the
same way under all three modes and are **read** under all three, so the test can
tell the difference between "ignored" and "my probe is blunt".

This is the same class as part 2's S8 (the Gaussian-PIC hybrid silently ignoring
`grid_extent`) and is fixed the same way — rejected, in the constructor and again
in `_validate_pic_solver`, matching how every other option in this file is
validated. Nothing in `test/`, `validation/` or `examples/` combined the two.

The fix made `SolverOptionEffectivenessContract` fail, because its PIC probe sets
`grid_extent = :sigma` (deliberately, so `grid_extent_sigma` can act) and its
`interaction_grid` alternative is `:source_slice`. That is the contract working.
An alternative may now be a `NamedTuple` carrying a companion setting, and the
companion is applied to the option's **baseline** as well, so the comparison
still isolates the option under test rather than measuring the companion.
Coverage is unchanged: 68 CPU options, 10 CUDA-only, 2 launch surfaces.

## 6. Areas checked and found sound

The point of the pass. Each of these was checked against something independent,
not merely read.

- **The three `_run_logical_workers` sites** (`_pic_deposit_threaded!` ×2,
  `_pic_deposit_drifted_threaded!`) — the part 1 §3 closure-capture class,
  checked on **lowered code** as that section requires, not by grep. All three
  clean: `Core.Box = false`. The `local_grid` name is assigned both inside the
  `do` block and in a following `for` header, which is the exact shape that gave
  six false positives to a text sweep — and `for` opens a scope, so it is a
  genuine false positive here too.
- **The integrated Green kernel**, derived by hand (§2.1) including the
  continuity at `x = 0` the four-corner difference depends on.
- **The lattice kernel normalization**, derived independently (§2.2).
- **TSC and CIC weights**, derived (§2.3) and checked to sum to 1 in range and 0
  out of range.
- **The luminosity path**, against the closed-form Gaussian overlap
  `1/(2π√(σ₁ₓ²+σ₂ₓ²)√(σ₁ᵧ²+σ₂ᵧ²))`, 200,000 particles per beam:

  | deposit | grid 64 | grid 128 | grid 256 |
  |---|---|---|---|
  | CIC | −3.644e−3 | −7.834e−4 | −1.978e−4 |
  | TSC | −5.535e−3 | −1.245e−3 | −2.781e−4 |

  Ratios 4.65 / 3.96 and 4.45 / 4.48 — clean second-order convergence to the
  analytic value. This validates the weights, the `h_x h_y` normalization and the
  `klum` scale together.
- **`_pic_align_grid_origins`** — derived (§2.4). Its `t > 0.5` / `t < −0.5`
  branches are unreachable (`t = (f₂−f₁)/2 ∈ (−0.5, 0.5)` since `f₁,f₂ ∈ [0,1)`),
  which is harmless dead code, not a defect.
- **The `:extrema` margin claim.** `_pic_cic_weights`' docstring says its
  out-of-range branch is unreachable under `grid_extent = :extrema`. Derived:
  `h_x = t_x` exactly, so `u ∈ [1.5, n−2.5]`; measured `[1.591, 61.591]` at
  `n = 64`. True, and it holds for the wider TSC stencil too.
- **`_pic_field!` boundary stencils** — the one-sided forms `(1.5φ₀ − 2φ₁ +
  0.5φ₂)/h` are the standard second-order one-sided first derivative, sign
  consistent with `E = −∇φ`; the fourth-order interior stencil
  `[(φ_{i+2}−φ_{i−2}) + 8(φ_{i−1}−φ_{i+1})]/(12h)` is the standard form.
- **The field/source drift bookkeeping.** The bounds initializer at
  `_pic_interaction!` l. 476–477 computes `field.x[1] + (0.5(z−c))·px[1]` with
  the same association as the loop's `s * field.px[i]`, so the initial min/max is
  bit-identical to the value the loop then writes. Checked because an off-by-one
  there would silently shrink the box by one particle.
- **The `:node` longitudinal path.** `phi_L − phi_Z` is evaluated with both
  planes on `gL`'s mesh, as its docstring requires — the transverse blend reads
  each node on its own mesh, the longitudinal difference does not. Confirmed by
  reading which grid each `_pic_interpolate_kick` call is handed.

## 7. Corrections to this audit's own analysis

Two hypotheses this pass raised and its own measurements killed. Both are kept
because a wrong turn that is visible is worth more than a clean story.

### 7.1 "`_pic_green!` iterates a column-major array in row-major order, so it is
slow." — **Refuted.**

The observation is true: `for i in 0:(2nx-1), j in 0:(2ny-1)` writing
`green[i+1, j+1]` walks with stride `2nx`, and the sibling
`_pic_green_lattice!` twenty lines below already loops the other way. The
inference was wrong. Measured at grid 128, bit-identical output:

```
shipped (i-outer)   4.950 ms
contiguous (j-outer) 4.990 ms   speedup 0.99x
```

No difference, because the loop body is four `_pic_kernel_integral` calls, each a
`log` and two `atan`. It is compute-bound; memory order is irrelevant. **Not
changed.** The lesson is the protocol's own: measure rather than speculate, and
"this loop is transposed" is a hypothesis, not a finding.

### 7.2 "The alignment fix should visibly improve the `:lattice` transverse kick."
— **Not demonstrated.**

The first attempt compared `:lattice` against `:integrated` on aligned, expanded
and re-aligned grid pairs, and the misaligned case came out *better*
(8.63e−2 against 1.00e−1). That comparison is worthless: the three grid pairs
have different cell sizes and different aspect ratios, so it was measuring the
lattice kernel's ρ-sensitivity, not the alignment. Recorded because it is the
kind of number that would have been easy to quote in the wrong direction.

The second attempt held the grid fixed and scored against the exact
Bassetti–Erskine kick, which is the right comparison, and gave 1.02x (§3). End to
end at grid 64 against a grid-512 reference, cache-on and cache-off differ by
less than the discretization error either carries. **The defect is confirmed
mechanically and the physics gain is not demonstrated**, and §3 says so.

## 8. Test, contract, validation and performance report

Julia 1.12.4, Linux 5.14.0, 128 logical cores, CUDA device visible and
functional.

### Tests

`Pkg.test(; julia_args=["--threads=4"])` — **passing**, including the CUDA
testsets. Three testsets added:

- `Green-cache expansion preserves the grid alignment its kernels require`
  (19 assertions) — checks the invariant before expansion, checks that the
  expansion **breaks** it (the negative control, so the test cannot pass
  vacuously), checks the realignment restores it, checks `:integrated` is left
  untouched, and checks `_pic_green_lattice!` accepts an aligned pair and rejects
  a 0.4-cell misaligned one.
- `grid_extent is rejected, not ignored, where no estimator runs` (7) — including
  that `:slice_pair` still accepts it, so the check cannot pass by forbidding the
  option outright.
- `Dropped PIC charge reaches a reader` (5) — `@test_logs` that the default is
  silent and that an under-covering estimator is not.

### Contracts — all pass

| contract | status |
|---|---|
| `StrongStrongPICBackendConsistencyContract` | passed |
| `StrongStrongGaussianBackendConsistencyContract` | passed |
| `ElementParameterEffectivenessContract` | passed (238 parameters) |
| `KnobEffectivenessContract` | passed |
| `PTCConsistencyContract` | passed (55 cases, worst 5.0e-13) |
| `PublicConfigurationEffectivenessContract` | passed |
| `SolverOptionEffectivenessContract` | passed (68 CPU, 10 CUDA-only, 2 launch surfaces — coverage unchanged) |
| `CoherentModePhysicsContract` | passed |
| `HighEnergyWeakStrongLimitContract` | passed |
| `SymplecticityContract` | passed |
| `ElementTrackingBackendConsistencyContract` | passed (via the suite) |

### Validation

| script | result |
|---|---|
| `pic_gaussian_field_validation.jl` | median relative error 3.46e-4 … 4.60e-4 across five aspect ratios — unchanged |
| `pic_grid_extent_stability.jl` | `:extrema` 5.31e-2 / `:sigma` 6.46e-3 slice-to-slice, `dropped = 0` — matches the recorded history |
| `tracking_backend_consistency.jl` | global relative error 9.42e-16, `passed_tolerance = true` |

### Behavioural fingerprint

Captured before the first modification (Phase 13) and re-captured after all
fixes: luminosity, `sum(abs, coords)` and `coords[1]` at 17 significant digits,
over 14 solver configurations. **Bit-identical in 12 of 14.** The two that moved
are `green_type = :lattice` and `green_type = :standard` with the default cache —
exactly the configurations S14 targets, and nothing beside them. In particular
the default, `green_cache = :none`, `:lattice`/`:standard` without the cache,
`:TSC`, `:fourth`, `:quadratic`, `:node`, `:source_slice`, `:sigma`,
`grid_quantize` and `longitudinal_kick = false` are all unchanged to the last
bit.

### Performance

`_pic_field!`'s `Ey` pass, grid 128, bit-identical output, decomposed:

| variant | time |
|---|---|
| i-outer, no `@inbounds` (shipped) | 42.8 µs |
| i-outer, `@inbounds` | 42.4 µs |
| j-outer, no `@inbounds` | 4.8 µs |
| j-outer, `@inbounds` (now) | **3.0 µs** |

Loop order is the cause (8.9x); `@inbounds` adds 1.6x; 14.3x together. The `Ex`
pass below it was already contiguous, which is what made the asymmetry visible.

**Honest share:** at ~256 calls per collision this is ~11 ms of a ~2 s collision
at grid 128, about **0.5%**, which is below the run-to-run wall-clock noise on
this machine. Taken because it is free and bit-identical, not because it moves a
total. No regression anywhere: the fingerprint above is unchanged.

## 9. Handoff — where the next session starts

### Done, do not redo

| area | state |
|---|---|
| `src/tasks/strongstrong/pic_cpu.jl` | **read in full**; four defects fixed |
| The integrated and lattice Green kernels | independently derived, normalization confirmed |
| The luminosity path | verified against the analytic Gaussian overlap, second-order convergence confirmed |
| `Core.Box` class in this file | all three fan-out sites checked on lowered code, clean |
| Contracts | all run and passing; solver-option coverage unchanged at 68/10/2 |

### Next, in priority order

1. **`src/tasks/BeamObservers.jl` (1,446)** — only l. 700–1030 read (part 2).
2. **`src/knobs/Knobs.jl` (896) + `symbolic.jl` (285)** — only the epoch handshake
   read; `symbolic.jl` was declared in scope in part 2 and never reached.
3. **`src/tasks/strongstrong/pic_cuda.jl` (5,807)** — the wavefront scheduler and
   Green cache. Now carries a *specific* question rather than a general one: §3
   shows the CUDA cached-prep path mirrors the CPU one closely enough to have
   inherited S14 verbatim. Look for the other invariants it mirrors.
4. `spectral.jl` (1,045) and `spectral_cuda.jl` (760) — untouched by any audit.

### Two things this pass could not settle

- ~~**`:lattice` accuracy against the theory note.**~~ **Closed in a follow-up the
  same day, and it was a real defect — see §10.**
- **The `:node` path has no dropped-particle accounting.** `_pic_interaction_node!`
  never counts, so `dropped` is structurally zero there. It does not matter today
  because S16 now forbids `grid_extent ≠ :extrema` under `:node`, and `:extrema`
  covers by construction — but the two facts are only accidentally consistent,
  and lifting S16's restriction without adding the count would reintroduce a
  silent charge loss.

### Techniques that found things this pass

- **Ask who guarantees a consumer's assumption, then check the guarantee still
  reaches it.** S14 is entirely this. The comment above `_pic_green_lattice!`
  named `_pic_align_grid_origins` as its guarantor; the question that found the
  defect was whether anything sits between them.
- **A census over lowered code answers "is this ever read?" definitively.** One
  loop over every method in the module settled S15 in seconds, where a grep would
  have found the validation script's unrelated `dropped` column and looked like
  coverage.
- **Test the option under every value of the option it interacts with.** S16 is a
  cross-product: `grid_extent` works, `interaction_grid` works, and one silently
  erases the other. The contract tests options one at a time against a fixed
  probe and cannot see this class.
- **Carry a control through every ignored-option test.** `grid_quantize` and
  `min_transverse_extent` being *read* under all three modes is what makes
  "`grid_extent` is bit-identical" mean something.
- **A negative control in the regression test.** The alignment test asserts the
  expansion *breaks* the invariant before asserting the fix restores it —
  otherwise it would pass just as happily against a no-op.

---

# 10. Follow-up — S17, the `:lattice` question closed, and it was a defect

§9 left the `:lattice` accuracy discrepancy open as "probably a harness
mismatch, not a claimed contradiction". It was neither. It was a fourth defect in
this file, and the caution in §9 was the right instinct applied to the wrong
conclusion.

| # | severity | area | state |
|---|---|---|---|
| S17 | **Moderate** | the lattice Green function's periodic box is sized in *index* units, so at high aspect ratio it is physically far too flat; `:lattice` measured **10.3x worse** than the default kernel at the production aspect ratio, defeating the option's only stated purpose | fixed, verified |

## 10.1 Ruling out the harness first

No harness for the theory note's table was ever committed — `e3818be`, the commit
that added Section 3.4, touched `pic_free_space_kernels.md` and `todo.md` and
nothing else. So the note's numbers cannot be reproduced by construction, and the
only way forward was to re-measure with the repository's own documented
methodology: `validation/pic_gaussian_field_validation.jl`'s harness defaults
(deterministic 320² quantile source, 161² field points over ±4σ, TSC deposition,
median relative error against Bassetti–Erskine).

That reproduction is what turned a suspicion into a finding, because of one row:

| case | grid | note's `:lattice` vs `:integrated` | re-measured |
|---|---|---|---|
| round | 128 | 2.80x worse | **2.74x worse** |
| 11:1 | 128 | 1.48x **better** | **30.0x worse** |
| 25:1 | 128 | 1.37x **better** | **120x worse** |

The round-beam case reproduces almost exactly. Only the anisotropic cases
diverge, and they diverge by two orders of magnitude. A harness mismatch does not
behave like that.

The decisive observation was in the grid refinement: `:lattice` at 11:1 went
**3.21e-2 at grid 64 → 3.47e-2 at grid 128**, and at 25:1 1.54e-1 → 1.64e-1. It
got *worse* with refinement. Discretization error does not do that; a kernel that
is simply wrong does.

## 10.2 The mechanism

`_PIC_LATTICE_GREEN_MULT = 8` sets `Mx = 8·2nx`, `My = 8·2ny` — a multiple of the
padded extent **in index units**. The free-space limit needs the periodic box to
be large in **physical** units in every direction. The box is `Mx·hx` by `My·hy`,
so at `ρ = hx/hy = 11` it is eleven times flatter than it is wide; the
separations the table must cover span `±2nx` cells in x and `±2ny` in y, which is
eleven times *wider* than tall physically. The y-images therefore sit an order of
magnitude closer than the x-images and contaminate every separation far along x.

Measured on the table itself, as the spread of `G + ln r` (identically zero for a
true `−ln r + const`), over 24 separations:

| ρ | mult 8 (shipped) | 16 | 32 | 64 |
|---:|---:|---:|---:|---:|
| 1 | 8.744e-3 | 8.762e-3 | 8.766e-3 | 8.768e-3 |
| 5 | 1.325e-1 | 1.141e-1 | 1.105e-1 | 1.105e-1 |
| 11 | **2.663e-1** | 1.524e-1 | 1.227e-1 | 1.152e-1 |
| 25 | **8.917e-1** | 4.368e-1 | 4.367e-1 | 4.367e-1 |

**That table also contains this pass's own wrong turn.** It does not converge to
zero, and the first reading of it — "the kernel is broken at high ρ" — was too
strong. Decomposing by axis separates two different things:

| separation | mult 8 | mult 64 |
|---|---:|---:|
| (m=16, n=0) | −2.921e-2 | **3.986e-6** |
| (m=32, n=0) | −1.430e-1 | **−1.758e-3** |
| (m=0, n=8) | 1.234e-1 | 1.134e-1 |
| (m=0, n=16) | 7.650e-2 | 6.625e-2 |

The **x-axis** residuals vanish when the box grows: that is box contamination and
it is the defect. The **y-axis** residuals do not move at all: at ρ=11 a
separation of n cells is n/11 x-cells, so those points are inside the near-origin
region, and this is the *intended* anisotropic lattice correction the note
already documents ("at ρ=11 the correction is still ~5.9e-2 at r=16 in coarse-axis
cells" — measured here as 7.65e-2). Only the first of the two was ever wrong.

## 10.3 Fixed, and what it costs

The multiplier is now applied per axis and scaled by the aspect ratio,
`_pic_lattice_box_mult(ρ)`, enlarging the box on the fine-spacing axis and capped
at 64 to bound the auxiliary FFT. Symmetric in `ρ ↔ 1/ρ`, since
`_pic_interaction_grids` produces both.

Median relative field error, grid 64, before and after:

| aspect | `:integrated` | `:lattice` before | `:lattice` after |
|---|---:|---:|---:|
| round | **9.60e-4** | 1.74e-3 (1.81x worse) | 1.74e-3 (1.81x worse) |
| 5:1 | 2.33e-3 | 6.76e-3 (2.90x worse) | **1.93e-3 (1.20x better)** |
| 11:1 | 3.10e-3 | 3.21e-2 (**10.3x worse**) | **2.63e-3 (1.18x better)** |
| 25:1 | 3.70e-3 | 1.54e-1 (**41.5x worse**) | **3.18e-3 (1.17x better)** |

The qualitative claim in the theory note — worse for round beams, better for flat
ones — is now what the code actually does. It was not before.

**The cost is real and is not hidden.** One table at grid 128, ρ=11 goes from
0.26 s to 3.63 s. The note already records that a production run needs ~306
distinct tables, so that is ~18 minutes of table building per run. This
strengthens rather than weakens the existing "do not use in production"
recommendation; `:lattice` exists for field-accuracy studies, and a kernel that is
fast and an order of magnitude wrong is worth nothing to that purpose.

Round beams (ρ=1) get `(8, 8)` exactly as before, so every previously recorded
isotropic result stands unchanged — including the `a(1,0) = 1/4` check.

## 10.4 What remains open

At grid 128 the cap binds: ρ=11 wants an 88× box and gets 64×, leaving the
physical y-extent at 5.8× the region rather than 8×. `:lattice` there lands at par
with `:integrated` (1.18e-3 against 1.16e-3) rather than the 1.48x better the note
claims. That gap is bounded by the auxiliary FFT cost, not by anything
conceptual, and the note's own "concrete route to making it cheap" — a small
lattice patch near the origin plus the analytic asymptotic beyond — would remove
the constraint entirely.

## 10.5 Verification

Full suite passing at `--threads=4` including every CUDA testset; the `:lattice`
CPU/CUDA parity check still holds at `< 1e-13` (the table is built on the host and
uploaded, so one fix covers both backends). One testset added, *The lattice Green
box is sized in physical units, not index units* (14 assertions): the multiplier
is aspect-scaled, symmetric under `ρ ↔ 1/ρ`, and capped; the coarse-axis residual
— the part box contamination destroys, as opposed to the fine-axis near-origin
correction, which is expected to remain — is bounded at 1e-2, against a pre-fix
value of 1.4e-1 at ρ=11.

## 10.6 The lesson worth keeping

**A dimensionless criterion needs its units named.** "The box must be a
comfortable multiple of the padded extent" is true and was implemented faithfully;
it is simply not the same statement in index units and in physical units, and the
two coincide exactly when ρ = 1 — which is the only aspect ratio the shipped test
ever checked. That is the same failure shape as the note's own recorded near-miss
on the normalization, where `2π/(h_x h_y)` and a bare `2π` coincide at
`h_x = h_y = 1` and an isotropic sanity check could not separate them. The same
blind spot, in the same file, caught twice by the same question: **what does this
check fail to distinguish at ρ = 1?**
