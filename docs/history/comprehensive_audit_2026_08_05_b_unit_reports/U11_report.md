# U11 — spectral.jl / spectral_cuda.jl twin pair

**Reading unit:** U11. **Commit audited:** `7de4d81`. **Date:** 2026-08-05.
**Device:** RTX 4500 Ada, CUDA 13.0, Julia with `--threads=4`.

## Region and depth

| File | Lines | Depth |
| --- | --- | --- |
| `src/tasks/strongstrong/spectral.jl` | 1–1153 (all) | full line-by-line |
| `src/tasks/strongstrong/spectral_cuda.jl` | 1–913 (all) | full line-by-line |

Read side by side, routine by routine. The diff `6a3f39ab..HEAD` over the pair
(+4 / +188 lines: the R9 tripwire port and the R12 CUDA hoist) was read first
and is the anchor of the hypothesis.

Cross-file material consulted **only** to resolve seams, not audited:
`slicing.jl` (`_slice_collision_order`, `collision_pair_batches`,
`_slice_interpolation_parameters`, `_live_flags`/`is_live`), `pic_cuda.jl`
(`_cuda_longitudinal_slices`), `docs/theory/spectral_sine_poisson_solver.md`,
`test/runtests.jl` (existing R9/parity pins).

## Provenance

- **Read:** every line of both files; the theory note §1–§14; the prior U9 report.
- **Executed:** 8 probe scripts in session scratch
  (`/tmp/claude-320114/.../scratchpad/audit/p1…p8`), all read-only.
  No repository file was modified.

---

# LEADS

### LEAD U11-1 [Medium, confidence high] src/tasks/strongstrong/spectral_cuda.jl:49-50 (identical copies at 440-441 and 473-474)
Claim: The CUDA R9 dropped-charge tripwire reports **exactly zero** for the most
severe charge loss it exists to catch — a deposit coordinate far enough out of
the box to take `_grid_floor`'s `_GRID_REJECT` branch, or NaN/Inf — while the CPU
twin counts every such particle as a full unit of dropped charge; in the
transition band it reports magnitudes larger than all the charge in the
collision.
Mechanism: The CPU tripwire is a **conservation check** on the grid total,
`deficit = ns - sum(rho)`; the CUDA one is a **per-thread subset-sum**,
`clipped = w11 + w21 + w12 + w22 - written`. When `_grid_floor` returns
`_GRID_REJECT = typemin(Int)>>2 ≈ -2.31e18`, `wx = X - i ≈ 2.3e18`, so `1 - wx`
evaluates to exactly `-wx` (the `1` is far below the ulp of 2.3e18). The four
weights become `∓wx·(1-wy)` and `∓wx·wy`, `written` is 0 because all four
bounds guards fail, and the sum cancels to **exactly 0.0** instead of 1.0 — so
`clipped > 0` is false and no atomic fires. For NaN the weights are NaN,
`NaN > 0` is false, and again nothing fires. The stated invariant in the comment
("written charge is summed in the same term order as the full stencil total, so
the difference is exactly 0.0 when every node lands in the box") is true, but the
converse it silently relies on — that the difference is the clipped weight when
nodes *don't* land in the box — holds only while the weights are well
conditioned. A count of *which* stencil nodes were skipped (rather than a
difference of their weights) would be exact for every input.
Repro:
```
julia --startup-file=no --threads=4 --project=. p7_blowup.jl
```
Kernel level, `Nx=Ny=16`, `L=1e-3`, 63 in-box particles plus one at `x`:

| x | X=(x+L)/hx | CPU deficit | CUDA `ws.dropped` |
| --- | --- | --- | --- |
| 1e10 | 8.50e13 | 1.0000 | 1.0000 |
| 1e11 | 8.50e14 | 1.0000 | 1.0000 |
| **1e12** | **8.50e15** | **1.0000** | **0.0000** |
| 1e13 | 8.50e16 | 1.0000 | 0.0000 |
| NaN | — | 1.0000 | 0.0000 |
| Inf | — | 1.0000 | 0.0000 |
| 8×NaN | — | 8.0000 | 0.0000 |

Collide level, 6D path, `grid=(64,64)`, `nslices=2`, 256 particles/beam,
`kbb1=kbb2=kbb` (the recorded R9 configuration with the coupling swept):

| kbb | max\|x\| after | CPU warns / total dropped | CUDA warns / total dropped |
| --- | --- | --- | --- |
| 1e8 | 2.54e9 | 4 / 512 | 1 / 512 |
| 1e9 | 2.54e10 | 4 / 512 | 1 / **1354** |
| 1e10 | 2.54e11 | 4 / 512 | 1 / **1774** |
| 3e10 | 7.62e11 | 4 / 512 | 1 / 384 |
| 1e11 | 2.54e12 | 4 / 512 | 1 / 128 |
| **1e12** | 2.54e13 | **4 / 512** | **0 / 0** |

There are only 512 units of charge in the collision, so the 1354 and 1774 rows
are garbage magnitudes, and the 1e12 row is total silence. No coordinate is
non-finite in any row (checked): the whole effect is the `_GRID_REJECT`
cancellation. Reachability: only the huge-finite branch is reachable through
`collide!` — a NaN/Inf coordinate present *before* the collision is either
rejected by the `_spectral_box` non-finite chokepoint or, under
`allow_lost_particles`, excluded from the slices by `is_live`; the huge-finite
branch is produced *by* the collision itself in a blow-up, which is exactly the
regime R9 was written for.

### LEAD U11-2 [Low, confidence high] src/tasks/strongstrong/spectral_cuda.jl:279-287
Claim: The CUDA warning's `dropped_fraction` is diluted by a denominator that
includes deposits which structurally cannot clip, so the same physical event
reads 8.5× quieter than on the CPU and the reported number is not comparable
across backends.
Mechanism: The CPU warns per solve with `deficit / ns`, `ns` being that solve's
own source count. The CUDA flush warns once per collision with `dropped / ndep`,
`ndep` being every deposit launched anywhere in the collision — including the
luminosity-grid deposits, whose box covers its own extrema by construction (I
confirmed they contribute 0). At the recorded R9 configuration the luminosity
deposits are 1024 of the 3072-count denominator, i.e. a third of it is inert
padding. At production settings (15 slices, 6D, `m` particles per slice) the
denominator is `225 × 6m = 1350m` against the CPU's `m`, so a solve that drops
100% of its charge is reported as a 7.4e-4 fraction. The 1e-9 threshold is not
practically defeated (a total loss still reads 7.4e-4), but the *severity* the
warning conveys is desensitised by ~1350× and the two backends' numbers cannot
be compared.
Repro:
```
julia --startup-file=no --threads=4 --project=. p3_tripwire_detail.jl
```
Section (4): CPU per-solve ledger `[0.8315, 0.3359, 0.8315, 0.3359] × 128`;
CPU worst-solve fraction **8.3155e-01**, CUDA reported **9.7291e-02**
(`ndeposits=3072`) — quieter by **8.5×**. The *aggregate* is exactly right:
CPU total dropped charge **298.876726** == CUDA total **298.876726**.

### LEAD U11-3 [Low, confidence high] src/tasks/strongstrong/spectral_cuda.jl:283-284 vs spectral.jl:411-412
Claim: The two tripwires emit the same message string but different structured
payload keys — CPU `nsource`, CUDA `ndeposits` — so any log consumer, grep, or
test keyed on one will silently miss the other backend.
Mechanism: The message text is byte-identical (verified), but the `@warn` kwarg
set differs: CPU `{box, dropped_fraction, maxlog, nsource}`, CUDA
`{box, dropped_fraction, maxlog, ndeposits}`. This is a deliberate rename (the
quantities genuinely differ, see U11-2), but nothing states the relationship and
no test asserts either key.
Repro: `p3_tripwire_detail.jl` section (4) final line prints both key sets.

### LEAD U11-4 [Low, confidence high] src/tasks/strongstrong/spectral_cuda.jl:686-719 and 639-681
Claim: `field_precision=:single` reaches beyond the field solve: it downgrades
the **6D luminosity** and the **6D kick scale** to `Float32`, while the
transverse path keeps both in `Float64`. The option is documented as selecting
"the CUDA field-solve precision".
Mechanism: `_cuda_spectral_luminosity_idx_snap!(solver, ws::_SpectralCudaWS{T}, …)`
takes `T` from the **workspace**, so under `:single` the drift `s1/s2`, the
extents, `hx`/`hy`, the `qlum` accumulators and the final
`lum * T(klum) / (hx*hy)` are all `Float32`. `_cuda_spectral_luminosity_pair`
(transverse) instead sets `T = eltype(x1)`, the coordinate type, so it stays
`Float64` regardless. Same asymmetry for the kick scale:
`_cuda_spectral_collision_direction_6d*!` passes `T(kbb_slice)` with `T` = the
workspace type, where the transverse path uses `a1 = T(slices1.weight[i]*kbb2)`
with `T = eltype(beam1.rep.x)`.
Repro:
```
julia --startup-file=no --threads=4 --project=. p8_single.jl
```
8 slices, n=4000, `grid=(32,32)`: `longitudinal_kick=false` gives
`:single` luminosity **bit-identical** to `:double` (rel diff 0.000e+00);
`longitudinal_kick=true` gives rel diff **1.262e-07** ≈ `eps(Float32)`.

### LEAD U11-5 [Low, confidence high] src/tasks/strongstrong/spectral_cuda.jl:394 (also 529, 543)
Claim: The three CUDA solve entry points cannot survive an empty source
(`ns == 0`) — the launch `blocks=cld(ns, threads)` becomes 0 and CUDA rejects
it — while their CPU twins carry an explicit `ns == 0` branch
(`invn = ns > 0 ? 1/(a*b*ns) : 1/(a*b)`), which the CUDA code faithfully copied.
Mechanism: One side of the twin anticipates an input the other side crashes on.
Not reachable through `collide!` today (both CUDA entry points skip empty slices
with `length(idx) == 0 && continue`), so this is a latent-trap / dead-branch
divergence, not a live defect. Worth noting because the dead `ns > 0` ternary
reads as a guarantee the kernel launch does not honour.
Repro: `p6_corners.jl` section (2) →
`ns=0 _cuda_spectral_field! : THROWS Grid dimensions CuDim3(0x0,0x1,0x1) are not positive`.

### LEAD U11-6 [Low, confidence high, OUT OF HYPOTHESIS — test comment] test/runtests.jl, "CUDA spectral deposit tripwire (R9, U9-1)" testset
Claim: The comment "No transverse-path assert: that map never moves x/y inside
the collision, so its deposits cannot clip" is false. The transverse map's
deposits do clip, on both backends, at plausible settings — the CPU tripwire
docstring names the mechanism itself ("small grids (Nx < ~41), where the 5%
headroom is thinner than one cell").
Mechanism: The premise (no intra-collision motion) is correct — I verified it
directly — but it is not the only route to clipping. When
`L = max(d·σ, 1.05·emax)` is set by the `1.05·emax` branch (any beam whose
extremum exceeds `d/1.05` times its rms — an outlier or halo), the outermost
particle's CIC stencil straddles the wall on a coarse mesh. Measured with
`longitudinal_kick=false`:

| domain_factor | grid | CPU warns | CUDA warns |
| --- | --- | --- | --- |
| 4.0 | 16 | 2 | 1 |
| 4.0 | 32 | 2 | 1 |
| 5.0 | 32 | 2 | 1 |
| 8.0 | 32 | 2 | 1 |
| 2.0 | 64 | 0 | 0 |
| 16.0 | 8 | 0 | 0 |

Repro: `p3_tripwire_detail.jl` section (5).

### LEAD U11-7 [Low, confidence med, documentation] docs/theory/spectral_sine_poisson_solver.md §13
Claim: The recorded CPU/CUDA agreement figure ("kicks ~4e-16, luminosity
~9e-16") understates the 6D `pz` divergence by ~30×, and the CUDA path's
run-to-run nondeterminism is documented in exactly one inline comment inside the
**transverse** function while the largest spread I measure is in the **6D** one.
Mechanism: `pz` is accumulated from a **difference of two potentials**
(`Kz = phiL - phiR`), so the cancellation amplifies the relative divergence well
past the transverse kick's. Separately, the deposit atomics make every CUDA run
non-reproducible; the only statement of this in the source is
`spectral_cuda.jl:592-593`, inside `_cuda_spectral_collide_transverse!`.
Repro: `p4_hoist_parity.jl` / `p5_ordering.jl` — 6D `pz` CPU-vs-CUDA
**1.08e-14 … 1.23e-14** relative; CUDA 6D `pz` run-to-run spread **6.65e-15**.

---

# The tripwire-fires demonstration

The CUDA tripwire **does fire**, on both maps, with the CPU's exact message text.

**1. Recorded R9 configuration (6D, strong intra-collision kick).**
`grid=(64,64)`, `nslices=2` `:equal_count`, 256 particles/beam, `kbb=1e-4`:

```
CPU  : 4 warnings, per-solve dropped_fraction = 8.3155e-01, 3.3594e-01,
                                                8.3155e-01, 3.3594e-01  (nsource=128)
       total dropped charge = 298.876726
CUDA : 1 warning,  dropped_fraction = 9.7291e-02  (ndeposits=3072)
       total dropped charge = 298.876726
message text identical: true   payload keys identical: false (nsource vs ndeposits)
```

**2. Small-grid / outlier corner (transverse map).** `grid=(8,8)`,
`domain_factor=1e-6`, `longitudinal_kick=false`: CPU 2 warnings
(`dropped_fraction = 6.1384e-03`, `nsource=128`), CUDA 1 warning
(`dropped_fraction = 1.0231e-03`, `ndeposits=1536`).

**3. Kernel-level equivalence of the measured quantity.** Same source, same box,
CPU grid deficit vs CUDA in-kernel accumulator:

| case | CPU `ns - sum(rho)` | CUDA `ws.dropped` | \|diff\| |
| --- | --- | --- | --- |
| all inside | 0 | 0 | 0 (exactly) |
| one fully outside | 1.0000000000000426 | 1.0 | 4.3e-14 |
| several straddling, Nx=16 | 0.94199999999999... | 0.94200000000000... | 3.3e-16 |
| several straddling, Nx=128 | 3.8709999999999951 | 3.870999999999996 | 8.9e-16 |

Verdict: **the tripwire fires, and in the aggregate it measures the same
physical quantity as the CPU one to roundoff** (298.876726 vs 298.876726 on the
recorded case). Its defects are (a) total silence in the `_GRID_REJECT`/NaN
regime (U11-1), (b) a diluted, non-comparable reported fraction (U11-2), and
(c) a renamed payload key (U11-3).

---

# The R12 CUDA hoist: bit-identity verdict

**Verdict: bit-identity is not achievable on this backend, and the hoist is
exactly at the unchanged code's own nondeterminism envelope. The hoist's
mathematical premise is verified directly and holds.**

1. **Premise verified.** The hoist is valid iff the transverse map never mutates
   `x`/`y`. Measured on CUDA, 10 slices, 1200 particles/beam: `beam1.x`,
   `beam1.y`, `beam2.x`, `beam2.y` all **bitwise unchanged** across `collide!`.
   Same check on the CPU twin: `x`, `y`, `z`, `pz` all bitwise unchanged.
2. **Bit-identity is impossible in principle here.** The deposit uses
   `CUDA.@atomic rho[i,j] += w`, so `rho` — and therefore every field — is not
   reproducible run to run. Baseline: calling `_cuda_spectral_field!` seven times
   on the *same* source gives non-identical `Exg`, max relative deviation
   **4.19e-16 … 5.59e-16**.
3. **Hoist vs an explicit pre-hoist pair loop.** I reconstructed the pre-hoist
   loop verbatim from the diff (solve the source field inside the pair loop,
   `2·n1·n2` solves) and ran it against `collide!` on identical inputs:

   | comparison | px | py | luminosity |
   | --- | --- | --- | --- |
   | same code, run vs run | 3.947e-16 | 3.948e-16 | **0** (bitwise equal) |
   | hoist vs pre-hoist | 3.947e-16 | 3.948e-16 | **0** (bitwise equal) |

   The hoist-vs-pre-hoist difference is **identical to the same code's own
   run-to-run envelope**, to three digits, and the luminosity is bitwise equal.
   The kick accumulation is therefore unchanged term for term as the comment
   claims; only the atomic ordering moves.
4. **The CPU R12 split is bit-identical**, re-verified:
   `_spectral_field_grid_solve!` + `_spectral_field_grid_eval` == the fused
   `_spectral_field_grid!`, **bitwise true** for both `Ex` and `Ey`.
5. **`ndep` bookkeeping matches the hoist.** The tripwire counts `n1+n2` source
   deposits (one per hoisted solve) plus the per-pair luminosity deposits —
   consistent with what the hoisted code actually launches.
6. Note (not a defect): the hoist holds `2(n1+n2)` device field meshes alive
   simultaneously — 23 MB at the production `(127,383)`×15 slices, 63 MB at
   `(128,1024)`×15. The comment does not mention the memory trade.

---

# Twin comparison table

| CPU routine (`spectral.jl`) | CUDA routine (`spectral_cuda.jl`) | Guards | Op order | Constants | Boundary conv. | Verdict |
| --- | --- | --- | --- | --- | --- | --- |
| `_grid_floor` | same function, device-compiled | = | = | `_GRID_REJECT` = | = | **same code** |
| deposit loop, `_spectral_field_grid_solve!` | `_cuda_spectral_deposit_kernel!` | = (`1<=i<=Nx && 1<=j<=Ny` ×4) | CPU nested tuple loop, CUDA 4 explicit ifs — same 4 terms | = | = | equivalent; `rho` rel **8.9e-16**, not bitwise (atomics) |
| `_spectral_deposit_tripwire` | in-kernel `clipped` + `_cuda_spectral_deposit_tripwire_flush!` | ≠ | ≠ | threshold `1e-9` = | = | **DIVERGES** — U11-1/2/3; aggregate equal (298.876726 both) |
| `_spectral_field_grid_solve!` transforms | `_cuda_spectral_field!` | n/a | CPU 2D-RODFT00 plan, CUDA DST1∘DST2 | `-2π` = , `G=1/(al²+bm²)` = , `invn` = | = | Exg rel **4.9e-16**, Eyg **5.6e-16** |
| `_spectral_field_grid_potential!` | `_cuda_spectral_potential_solve*!` → `_cuda_spectral_solve_from_rho!` | n/a | CUDA folds `scale` into the extract; CPU applies after | `0.5*scale` on Φ = | = | Phig rel **6.4e-16** (29 ulp) |
| `_spectral_field_grid_eval` | `_cuda_spectral_interp_scatter_kernel!` | = | = | `hx=(2Lx)/(Nx+1)` bit-identical | out-of-range node skipped ⇒ E=0 at wall, **both** | equivalent |
| `_spectral_interaction!` | `_cuda_spectral_interp_scatter_6d_kernel!` | = | = (drift → `pz -= .25p²` → kick → `pz += .25p²`) | `_slice_interpolation_parameters` inlined **identically** (`hzi=0, zbias=0.5` degenerate branch matches) | = | equivalent; pz rel **1.2e-14** |
| `_spectral_box` | `_cuda_spectral_box` | = (live mask present on both) | `max` args in the same order | `d·smax` / `1.05·emax` = | = | equivalent |
| `_spectral_box_drifted` | `_cuda_spectral_box_drifted` | = | same order | = | = | equivalent |
| `_masked_rms` / `_masked_ext` | `_cuda_masked_rms` / `_cuda_masked_ext` | = (`nothing` = off state on both) | seq. vs tree reduction | CUDA adds `max(…,0)` under the sqrt | NaN→NaN on both | equivalent |
| `_spectral_luminosity_pair` | `_cuda_spectral_luminosity_pair` | = | `sum` loop vs `sum(q1.*q2)` | margin `0.1tx/0.05tx` = | = | equivalent; `T` = `promote_type(…)` vs `eltype(x1)`; index form `(x-x0)/hx+1` vs `(x-x0+hx)/hx` (roundoff, continuous) |
| `_spectral_luminosity_pair` on midpoint sources | `_cuda_spectral_luminosity_idx_snap!` | = | `sum` vs `dot` | same | same | **`T` = workspace type ⇒ Float32 under `:single`** (U11-4) |
| `_spectral_collide_transverse!` | `_cuda_spectral_collide_transverse!` | = | CPU parallel over field slices; CUDA sequential over `_slice_collision_order` — same pair set (all n1·n2) | = | = | equivalent, both R12-hoisted |
| `_spectral_collide_longitudinal!` | `_cuda_spectral_collide_longitudinal!` | = | CPU `collision_pair_batches` (conflict-free), CUDA strict order — same per-slice order | = | = | equivalent |
| `_spectral_field_free*`, `_spectral_mode_sum_guard`, `_spectral_cosderiv`, `_spectral_field_grid` | — | — | — | `+4π` | — | CPU-only; CUDA throws `ArgumentError` for `:grid_free` (verified in the suite) |
| — | `_cuda_ext1/2_kernel!`, `_cuda_extract1/2_kernel!`, `_cuda_dst1/2!`, `_cuda_cosderiv1/2!` | — | — | — | — | CUDA-only; conventions derived and verified below |

---

# Measured parity (hypothesis c)

`grid=(32,32)`, `kbb1=kbb2=1e-6`, `luminosity_scale=1.0`, 1200 particles/beam,
**10 slices** `:equal_width` over a bimodal `z` giving populations
`[600, 0, 0, 0, 0, 0, 0, 0, 0, 600]` — **8 of 10 slices empty**.

| case | map | max rel coord diff | worst coord | lum rel diff |
| --- | --- | --- | --- | --- |
| 10 slices, 8 empty | transverse | **4.54e-15** | py | **3.55e-16** |
| 10 slices, 8 empty | 6D | **1.23e-14** | pz | **1.45e-15** |
| + 6 dead particles (`allow_lost_particles`) | transverse | **3.76e-15** | py | **4.76e-16** |
| + 6 dead particles (`allow_lost_particles`) | 6D | **1.18e-14** | pz | **1.58e-15** |

The dead-particle rows also verify that the NaN pattern of every coordinate array
is identical on both backends (no mismatch printed).

Field-solve level, same source, 4000 particles, `grid=(32,48)`:
`rho` **8.9e-16**, `Exg` **4.9e-16** (117 ulp), `Eyg` **5.6e-16** (53 ulp),
`Phig` **6.4e-16** (29 ulp).

These are at the recorded ~1e-15/6e-16 level for the transverse map and the
field; the 6D `pz` sits at 1.2e-14 because it is built from a difference of two
potentials (see U11-7).

Repro: `p4_hoist_parity.jl`.

---

# Independent mode-sum verification (hypothesis d)

Written from `docs/theory/spectral_sine_poisson_solver.md` §4–§9 alone, then
compared to the code:

- `ρ_lm = (4/(ab)) ∫∫ ρ sin(α_l x) sin(β_m y)`, `α_l = lπ/a`, `β_m = mπ/b`
- `φ_lm = -ρ_lm/(α_l² + β_m²)` (no `l=0` — **there is no zero mode**, the
  denominator is bounded below by `(π/a)² + (π/b)² > 0`)
- source normalised to unit total charge (`/ns`)
- stated code convention `K = -4πE = +4π∇φ`, stored potential `Φ_code = -4πφ`

Evaluated at the interior mesh nodes so CIC interpolation error is out of the
comparison (`_spectral_field_grid_potential!` vs an O(N⁴) direct mode sum):

| grid | CIC deposit matches | Ex | Ey | Φ |
| --- | --- | --- | --- | --- |
| (12,10) | bitwise **true** | **1.100e-15** | **1.226e-15** | **6.571e-16** |
| (15,15) | bitwise **true** | **1.160e-15** | **1.685e-15** | **1.362e-15** |
| (16,24) | bitwise **true** | **1.805e-15** | **2.203e-15** | **2.264e-15** |

`:grid_free` at arbitrary field points against the same independent sum:
Ex **1.137e-15**, Ey **1.983e-15**, Φ **9.572e-16**.

Cross-check with no shared code path: for a source lying exactly on mesh nodes
(where CIC deposition is exact) `:grid` and `:grid_free` agree to
Ex **1.883e-15**, Ey **1.971e-15**, Φ **6.204e-16**.

Repro: `p1_modesum.jl`, `p1b_modesum_nodes.jl`.

**Where the factors live, checked term by term.** The two FFTW `RODFT00`s each
carry a factor 2, so `FFTW.r2r(rho, RODFT00)` = `4·Σ_ij ρ_ij sin sin`; dividing by
`a·b·ns` yields exactly the continuum `ρ_lm` — the `4` of `4/(ab)` is supplied by
the transform, not by a hand constant. On reconstruction each field component
carries one `RODFT00` (×2) and one padded `REDFT00` with an explicit `/2` (net
×1 on the derivative dimension), so `-scale·(cosx/2) = 4π ∂φ/∂x`; the potential
carries two `RODFT00`s (×4) and needs the extra `0.5` to land on `-4πφ`. The
`+4π` of `:grid_free` and the `-2π` of `:grid` therefore describe the same
physical field — confirmed numerically above, and by the `:grid`↔`:grid_free`
on-node comparison. The **CUDA** DST/DCT-via-rFFT conventions match FFTW's
analytically (odd extension of length `2(N+1)` ⇒ `-Im FFT_k = 2Σ A_j sin(πjk/(N+1))`
= `RODFT00`; even extension with zeroed ends ⇒ `Re FFT_k = 2Σ A_j cos(πjk/(N+1))`,
extracted with `cre = scale·0.5`) and numerically at 5e-16.

**Dirichlet boundary treatment.** The mesh is the interior only
(`x_i = i·h_x`, `h_x = a/(N_x+1)`, `i = 1…N_x`); the walls `x = 0, a` are not
stored. A CIC stencil node that falls on a wall is skipped, which is exactly
`φ = 0` there — the correct Dirichlet condition, and identical on both backends.
The **field** at the wall is not zero, so the same skip in
`_spectral_field_grid_eval` / `_cuda_spectral_interp_scatter_kernel!` is an
approximation for `E`, not an exact condition; it is a shared convention with no
twin divergence, and the field is small there by the box-sizing assumption.

---

# Accumulation ordering (hypothesis e)

Measured with 1 / 2 / 4 CPU workers and 4 repeat CUDA runs:

| configuration | map | CPU thread-count invariance | CUDA run-to-run |
| --- | --- | --- | --- |
| n=15000, 3 slices `:equal_count` (the repo's own pin) | 6D | lum **bitwise equal**, px/pz **bitwise equal** | lum **1 ulp** spread; px 4.25e-15, pz 2.80e-15 |
| n=4000, 8 slices `:equal_count` | 6D | lum **bitwise equal**, px/pz **bitwise equal** | lum **4 ulp**; px 4.25e-15, pz 4.10e-15 |
| n=1200, 10 slices, 8 empty | 6D | lum **bitwise equal**, px/pz **bitwise equal** | lum **3 ulp**; px 1.52e-15, pz **6.65e-15** |
| n=4000, 8 slices `:equal_count` | transverse | lum **1–2 ulp** (not bitwise); px **bitwise equal** | lum **bitwise equal**; px 3.95e-16 |

Findings:

1. The recorded 1-ulp thread-order effect **is not in
   `_spectral_collide_longitudinal!` any more** — that routine is now bitwise
   thread-count invariant in all three configurations, luminosity included. The
   residual 1–2 ulp fold-order effect lives in `_spectral_collide_transverse!`
   (`lum_parts` folded over a worker-count-dependent chunk grid). The repo's own
   pin is consistent with this: its first block allows `rtol=8·eps` for both
   spectral variants, and its second (bit-equality) block covers only
   `spectral_l`, not `spectral_t`.
2. The CUDA path has **no** thread-order dependence in the accumulation
   (`luminosity += …` is strictly sequential over `_slice_collision_order`), but
   it has a **larger** and different ordering dependence: the deposit atomics
   make every run non-reproducible. 6D luminosity 1–4 ulp, 6D `pz` up to
   **6.65e-15** relative. On the transverse map the luminosity happens to come
   out bitwise reproducible while the kick does not (3.95e-16).
3. It is **bounded** (roundoff-scale, ≤ ~7e-15 in the worst coordinate here) but
   **documented only for the transverse map**, in one inline comment at
   `spectral_cuda.jl:592-593`. Nothing in the 6D function, the file header, or
   the theory note says a CUDA collide is not reproducible. → U11-7.

Repro: `p5_ordering.jl`.

---

# Clean list (with the evidence that makes it checkable)

Each of these was compared side by side and, where a number is given, measured.

1. **Sine-Poisson solve — normalisation, eigenvalue, zero mode, Dirichlet
   treatment.** Verified against an independently derived continuum mode sum at
   the mesh nodes: **1.1e-15 … 2.3e-15** across three grids, with the CIC deposit
   matching bit for bit. `:grid_free` **1.1e-15 … 2.0e-15**. Cross-check
   `:grid`↔`:grid_free` on an on-node source **6e-16 … 2e-15**. No zero mode
   exists (`l,m ≥ 1`); the denominator `α_l²+β_m²` is bounded below.
2. **`_SPECTRAL_FIELD_SCALE_GRID = -2π` and `_SPECTRAL_FIELD_SCALE_FREE = +4π`
   are consistent with each other and with the derivation.** Both routes give
   the same `Ex`, `Ey`, `Φ` for the same source (item 1, on-node comparison), and
   the potential satisfies `K = -∇Φ_code` term by term in the mode expansion.
3. **CPU R12 split is bit-identical.** `_spectral_field_grid_solve!` +
   `_spectral_field_grid_eval` == `_spectral_field_grid!`, bitwise, both
   components.
4. **CUDA R12 hoist premise holds.** The transverse map mutates neither `x` nor
   `y` on either backend (measured bitwise); the hoist's difference from an
   explicit pre-hoist loop equals the same code's own run-to-run envelope
   (3.947e-16 vs 3.947e-16) with bitwise-equal luminosity.
5. **Tripwire measures the right quantity in aggregate.** CPU total dropped
   charge == CUDA total, exactly (298.876726) on the recorded R9 case; the
   kernel-level per-case agreement is 3e-16 … 4e-14. The luminosity deposits it
   shares an accumulator with contribute exactly 0, as the comment claims —
   confirmed by that exact equality.
6. **Deposit/interpolation stencils, guards and box conventions are twins.**
   Same four `1 <= i <= Nx && 1 <= j <= Ny` guards, same weights, same term
   order, same `hx = (2Lx)/(Nx+1)` expression (bit-identical), same
   `max(d·smax, 1.05·emax)` box with the `max` arguments in the same order, same
   `min_domain_halfwidth` floor and the same zero-half-width `ArgumentError`.
7. **The live mask reaches both box routines.** `_cuda_spectral_box` and
   `_cuda_spectral_box_drifted` both call `_cuda_live_flags(r, active_live_mask())`
   (the U9-era defect is closed); the dead-particle parity rows above exercise it
   end to end at 3.8e-15 / 1.2e-14.
8. **The 6D synchro-beam map is transcribed exactly.** Drift `s = 0.5(z - c_src)`,
   `pz -= 0.25(px²+py²)`, `zL = clamp(-z·hzi + zbias, 0, 1)`, kick, back-drift
   `s = 0.5(c_src - z)`, `pz += 0.25(px²+py²)` — same operations in the same
   order, with `_slice_interpolation_parameters`' degenerate branch
   (`hzi = 0, zbias = 0.5`) reproduced identically inside the kernel.
9. **Both backends solve the same pair set in a compatible order.**
   `_slice_collision_order` enumerates all `n1·n2` pairs; `collision_pair_batches`
   (CPU 6D) only groups conflict-free pairs and preserves per-slice order, so the
   6D result is order-equivalent — confirmed by the 6D parity numbers and by the
   CPU's bitwise thread-count invariance.
10. **Empty slices and `:grid_free` routing.** Every CUDA loop guards
    `length(idx) == 0 && continue` before touching the hoisted arrays, so no
    `#undef` slot is ever read; `:grid_free` on CUDA throws `ArgumentError` from
    both entry points. Exercised by the 8-of-10-empty-slice parity rows.
11. **Workspace leasing.** Both pools are lock-guarded, refuse double release,
    and the CUDA lease records/waits on a `CuEvent` and pins the device id. Read;
    no divergence found. (Concurrency was not stress-tested — see below.)

### Notes too small to be leads

- `spectral_cuda.jl:610` rebinds `W = eltype(ws.rho)`, shadowing the `W` computed
  at line 576. Same value; shadowing only.
- In the 6D kernel, `zbias = hzi == zero(hzi) ? eltype(x)(0.5) : field_rb * hzi`
  mixes the coordinate type and the workspace type, so under `:single` it infers
  `Union{Float32,Float64}`. It compiles and runs; style only.
- CPU luminosity deposits (`_spectral_cic_deposit!`) have no tripwire at all,
  while the CUDA ones feed `ws.dropped`. Inert today (they cannot clip), but it
  is an asymmetry in which deposits are instrumented.
- `_cuda_spectral_deposit_tripwire_flush!` sits inside the `try`, not the
  `finally`, so a kernel error suppresses the flush.

---

# Not checked, and why

- **Concurrency stress.** The CUDA workspace lease's event-based hand-off and the
  CPU lease pool were read but not raced (multiple simultaneous collides on one
  device). Out of a single reading unit's budget; it is a cross-cutting concern
  shared with `pic_cuda.jl`.
- **Performance.** The R12 hoist's claimed 2.44× and the file's other optimisation
  claims were not benchmarked; the brief scoped this unit to correctness and
  parity.
- **`:grid_free` numerical quality beyond the mode-sum check.** Its truncation
  behaviour, `_spectral_mode_sum_guard`'s threshold, and its convergence with
  mode count are physics-accuracy questions, not twin-divergence questions.
- **Cross-file seams**, flagged and stopped at per protocol: `slicing.jl`
  (`_slice_collision_order`, `collision_pair_batches`, `is_live`), `pic_cuda.jl`
  (`_cuda_longitudinal_slices`, `_cuda_live_flags`), `interface.jl`
  (`_strong_strong_kbb*`, `_run_logical_workers`, `_chunk_bounds`),
  `pic_cpu.jl` (`_pic_extract_slice`, `_pic_copy_coords`, `_pic_store_slice!`,
  `_slice_interpolation_parameters`). Each was read only far enough to confirm
  the twin contract; none was audited.
- **`field_precision=:single` beyond U11-4.** I established that it reaches the
  6D luminosity and kick scale; I did not survey every quantity it silently
  narrows.
