# U10 Audit Report — GaussianPICPoissonSolver CPU/CUDA twin pair

**Region:** `src/tasks/strongstrong/gaussian_pic.jl` (869 lines) and
`src/tasks/strongstrong/gaussian_pic_cuda.jl` (1,232 lines) — every line of both.
**Commit audited:** `7de4d81` (HEAD at the time of the pass).
**Prior unit report:** `docs/history/comprehensive_audit_2026_08_05_unit_reports/U8_report.md`
(commit `13c2733`).

## 0. Provenance — what was read, what was executed

**Read line by line, by this unit, in full:**

- `src/tasks/strongstrong/gaussian_pic.jl` 1–869.
- `src/tasks/strongstrong/gaussian_pic_cuda.jl` 1–1232.
- `docs/theory/gaussian_subtracted_pic_solver.md` 1–793 (whole note), with every
  boxed equation of §5, §6, §7.2 and §7.4 re-derived by hand against the code.

**Read as reference (targeted, outside the region — seams only):**
`pic_cpu.jl` 45–60, 110–165, 416–442, 488–660, 1057–1130, 1236–1272, 1300–1420,
1508–1533; `pic_cuda.jl` 1580–1720, 2640–2740, 2786–2850, 5645–5710;
`src/elements/strong_beam.jl` 1051–1122; `src/contracts/Contracts.jl` 2143–2420;
`src/elements/aperture.jl` (loss convention); `validation/gaussian_pic_field_validation.jl` 1–120.

**Provenance note carried forward.** The 2026-08-05 record's honest remainder
says the bulk of these two files was "agent-read only". This pass is also an
agent read — but every claim below that matters is backed by an executed
measurement, and the probe scripts are listed so a human can re-run them.

**First finding, cheap and important:**
`git diff 6a3f39ab HEAD -- src/tasks/strongstrong/gaussian_pic.jl
src/tasks/strongstrong/gaussian_pic_cuda.jl` is **empty**. Neither file changed
in the 63 commits since the last full audit. The one lead the previous pass
raised against this region (U8-1, the theory note claiming the coupled branch is
CPU-only) was closed in the *documentation*: `gaussian_subtracted_pic_solver.md`
§7.5 now ends "The two CUDA *reference* routes raise … the default CUDA
indexed-wavefront route implements the coupled subtraction (this paragraph once
said the branch was CPU-only — corrected by the 2026-08-05 audit, U8-1)".
Verified against the three code locations; the note is now correct.

**Executed** (all probes in
`/tmp/claude-320114/-cfs-ad-dxu/37c712a3-734a-4817-a05e-4c9e12cabcef/scratchpad/audit/`,
run with `julia --startup-file=no --project=/cfs/ad/dxu/Library/Julia/Octopus`,
GPU = RTX 4500 Ada, CUDA 13.0):

| probe | what it measures |
| --- | --- |
| `p1_parity.jl` | CPU↔CUDA parity, 4 required regimes × {CIC,TSC} × {lk,no-lk} × {indexed,non-indexed} |
| `p2_kickbreakdown.jl` | per-component kick difference, with plain-PIC and soft-Gaussian **controls** |
| `p3_dead_and_coupled.jl` | all-NaN (dead) particle on both backends; coupled-branch parity; mode census |
| `p4_fieldverify.jl` | total hybrid field vs direct O(N²) free-space sum and vs exact Bassetti-Erskine |
| `p5_options.jl` | schema-derived option census + `SolverOptionEffectivenessContract` |
| `p6_theory.jl` | erf profiles vs Gauss-Legendre quadrature; coupled expansion vs 2D quadrature; transport identities; neutralization; coupled box containment; validation-script drift |
| `p7_anchor.jl` | analytic add-back anchored to `_cp_covariance_kick`; response-vs-plain BE kick; b→0 continuity; cross-plane moment cost |
| `p8_routes.jl` | empty-slice census; `batch_mode=:sequential` parity; guard reachability |
| `p9_docclaims.jl` | the region docstring's own quantitative claims; `configuration_report` honesty |
| `p10_cache.jl` | parity under `green_cache=:slice_pair`, multi-turn, quantize, :fourth, :standard, Float32 |

No repository file was modified.

---

## 1. Leads

### LEAD U10-1 [Low, confidence high] src/tasks/strongstrong/gaussian_pic.jl:141-158
Claim: `configuration_report(::GaussianPICPoissonSolver)` reports `status=:resolved`
for the six options this solver *rejects* at collide time, and for
`grid_extent_sigma`, which it never reads — so the user-facing "what will
actually happen" surface says a setting is in force for a value that hard-errors.

Mechanism: `configuration_report` forwards
`configuration_report(solver.pic; policy, backend)` unmodified and appends only
the three Gaussian entries. For `PICPoissonSolver` those seven entries are
genuinely resolved; for the hybrid, `_require_linear_slice_interpolation`
(`pic_cpu.jl:416-437`) throws on non-default `slice_interpolation`,
`interaction_grid` and `grid_extent`, and `gaussian_pic_cuda.jl:87-95` throws on
`cuda_async/cuda_batch_fft/cuda_wavefront_fft = false`. Even at their *default*
values the hybrid does not read them — it hardcodes the slice-pair box, sizes
its own extent from `margin_sigma`, and picks its CUDA route from `batch_mode`
and `cuda_indexed_wavefront` alone (the code says so at
`gaussian_pic_cuda.jl:82-86`). The neighbouring `coupling_tol` entry
demonstrates the correct handling: it reports `:inactive_dependency` when `Inf`.
This is the "ignored configuration must warn, throw, or be documented as inert —
never vanish" rule applied to the report rather than to the run: the throw is
loud, but the report contradicts it.

Repro:
```
julia --startup-file=no --project=. -e '
using Octopus
s = GaussianPICPoissonSolver(grid=(64,64), grid_extent=:sigma)
for e in Octopus.configuration_report(s)
    e.name === :grid_extent && println(e.name, " -> ", e.status)
end'
```
prints `grid_extent -> resolved`, while `collide!` on that same solver throws
`ArgumentError: grid_extent = :sigma is not implemented by
GaussianPICPoissonSolver`. Full table in `p9_docclaims.jl` (last block).

---

### LEAD U10-2 [Low, confidence high] src/tasks/strongstrong/gaussian_pic.jl:775-820
Claim: `_gpic_collide!` neither resets nor reports `workspace.dropped[]`, while
its plain-PIC twin `_pic_collide!` does both — a latent silent dropped-charge
channel in a solver that shares the counter's workspace.

Mechanism: `_pic_collide!` sets `workspace.dropped[] = 0` (`pic_cpu.jl:55`) and
calls `_pic_report_dropped(workspace)` (`pic_cpu.jl:122`, `127`), which `@warn`s
on any non-zero count. `_gpic_collide!` calls `_pic_report_green_cache` only
(`gaussian_pic.jl:818`) and never touches `dropped`. The counter's only
increments (`pic_cpu.jl:619`, `632`) sit inside `if ge !== :extrema` in
`_pic_interaction!`, and the hybrid rejects every non-`:extrema` `grid_extent`
at `gaussian_pic.jl:779`, so **the channel is unreachable today** — this is a
missing guardrail, not an active loss. It matters because `_pic_interaction!` is
reachable from the hybrid (the `mode === :pic` fallback at
`gaussian_pic.jl:602-604`) with the *same* workspace, so the day the extent
estimator becomes usable here the count would both accumulate across turns and
never be surfaced. `_PICCPUWorkspace.dropped` documents itself as "Never
silent".

Repro:
```
julia --startup-file=no --project=. \
  .../p8_routes.jl   # section "e"
```
poisons `ws.dropped[] = 7`, runs `_gpic_collide!`, and reads `7` back; the same
sequence through `_pic_collide!` reads `0`.

---

### LEAD U10-3 [Low, confidence high, out-of-hypothesis: performance / twin asymmetry] src/tasks/strongstrong/gaussian_pic.jl:353,361-362,373-376
Claim: the CPU moment pass always accumulates the four cross-plane sums
(`sxy`, `sxpy`, `sypx`, `spxpy`) even under the default `coupling_tol = Inf`,
where they are provably unreachable; the CUDA twin gates the identical work on
`want_coupled`. Measured 33% overhead on the moment loop.

Mechanism: `_gpic_source_moments` has no coupling switch — it computes 14
accumulators unconditionally, and `_gpic_interaction!` then builds `cmom` at
line 698 and uses it only inside `if use_coupled`. With `coupling_tol = Inf`,
`_gpic_control_variate_mode` short-circuits on `isfinite(coupling_tol)`
(line 469) before it ever reads `bL.rxy`, so the four sums cannot change any
number. The CUDA side does gate: `_cuda_gpic_batched_moments(valid, rep1, rep2,
want_coupled)` selects `Val(true)`/`Val(false)` and the device kernel
accumulates 14 vs 10 slots (`pic_cuda.jl:5654-5710`). So the two backends
disagree about whether this work is optional — the CPU pays for it always. At
the recorded production point the slice moments are 3.2e-4 s of a 2.5e-2 s
interaction, so the waste is ≈0.3% of the interaction; the point is the
asymmetry, not the size.

Repro:
```
julia --startup-file=no --project=. .../p7_anchor.jl   # section 7d
```
prints `_gpic_source_moments` 0.0058 s/call at n = 2e6 against 0.0043 s/call for
the 10-accumulator equivalent → **33.4% overhead**.

---

### LEAD U10-4 [Low, confidence high, twin asymmetry in defensive shape] src/tasks/strongstrong/gaussian_pic_cuda.jl:732-735
Claim: `_cuda_gpic_gtuple` reads `m.cxy`, `m.cxpy`, `m.cypx`, `m.cpxpy`
directly, while its CPU twin `_gpic_coupled_moments` guards the identical
construction with `hasproperty` *specifically* because the CUDA non-indexed and
sequential routes build moment tuples without those fields.

Mechanism: `gaussian_pic.jl:389-400` carries the comment "Tolerant of moment
tuples built without the cross-plane terms (the CUDA non-indexed and sequential
routes do not compute them …); those degrade to the uncoupled covariance rather
than erroring", and implements it. `_cuda_gpic_gtuple` builds the same
`StrongTransverseMoments{T,true}` with bare field access. It is unreachable
today — `_cuda_gpic_gtuple` is called only from
`_cuda_gpic_launch_kick_pair_indexed!` (line 758), reached only from the indexed
route (line 419), whose moments always come from `_gpic_mom_from_coupled_sums`
or `_gpic_mom_from_gaussian`, both of which populate all four. But the guard
exists on one side of the seam and not the other, so the invariant that keeps it
safe is undocumented on the CUDA side, and this is host code feeding a device
kernel where a `FieldError` would surface as a compile failure.

Repro:
```
julia --startup-file=no --project=. -e '
using Octopus; const O=Octopus
src = (x=[1.0,2.0], px=[0.1,0.2], y=[0.5,0.7], py=[0.01,0.02])
mom = O._cuda_gpic_source_moments(src)
println(hasproperty(mom, :cxy))                       # false
println(try O._gpic_coupled_moments(mom); "OK" catch e typeof(e) end)   # OK
prep = (mom=mom, mode=:uncoupled, do_gauss=true, sL=0.0, sR=0.0,
        bL=O._gpic_boundary(mom,0.0), bR=O._gpic_boundary(mom,0.0))
println(try O._cuda_gpic_gtuple(Float64, prep); "OK" catch e typeof(e) end)'
```
prints `false`, `OK`, `FieldError`.

---

### LEAD U10-5 [Low, confidence high, CROSS-FILE SEAM — noted and stopped] validation/gaussian_pic_field_validation.jl:44-72
Claim: the validation script that produces the theory note's §9 accuracy table
carries its **own hand copy** of the erf node profile instead of calling
`_gpic_gaussian_profile!`, so the shipped profile in this region is not
exercised by the study that certifies it — a Measured-Lesson-4 hand copy with no
tripwire.

Mechanism: the script's header says both solvers are "exercised through their
real internals", but `gauss_profile` / `m0` / `m1` / `m2` at lines 44-72 are a
re-derivation, and it is that copy the subtraction uses. A regression in
`_gpic_gaussian_profile!` (the CIC/TSC branch, the `half`/`3half` cell edges, the
`1.125`/`1.5`/`0.5` weights) would leave this validation green. The copy has
**not** drifted — measured agreement 2.36e-16 (CIC), 4.27e-15 (TSC) — so this is
a coverage claim to repair, not a numeric defect. Seam ownership is the
auditor's: the fix could equally be "call the shipped function" or "keep the
independent implementation and add an equality tripwire", and that choice
belongs outside this unit.

Repro:
```
julia --startup-file=no --project=. .../p6_theory.jl   # section 6
```
prints `CIC max|shipped - validation-script copy| = 2.359e-16`,
`TSC … = 4.267e-15`.

---

## 2. Routine-by-routine twin comparison

Read side by side, not sequentially. "shared" means there is literally one
implementation that both backends call — the strongest possible parity, and the
dominant pattern in this pair.

| # | CPU (`gaussian_pic.jl`) | CUDA (`gaussian_pic_cuda.jl`) | Semantic difference |
| --- | --- | --- | --- |
| 1 | ctor + schema + `solver_configuration` 87–139 | — (host, shared) | none |
| 2 | `configuration_report` 141–158 | — | **U10-1** |
| 3 | `_pic_launch_solver` 163 | consumed by `_warn_inactive_pic_launch_config` 81 | none |
| 4 | `_gpic_gaussian_profile!` 176–207 | **shared**, called 492–493, 1050–1053 | none |
| 5 | `_gpic_central_moments` 242–255, `_gpic_shift_moments` 259–266, `_gpic_weighted_moments` 271–289, `_gpic_profile_mean_derivs` 296–318, `_gpic_coupled_profiles!` 320–338 | **shared**, called 346 | none |
| 6 | `_gpic_source_moments` 344–380 | `_cuda_gpic_source_moments` 453–480 (non-indexed/seq); `_cuda_gpic_batched_moments` 166–198 + `_gpic_mom_from_gaussian` 200–205 / `_gpic_mom_from_coupled_sums` 214–237 (indexed) | anchor: CPU `x[1]`; indexed CUDA `idx[1]` = **the same particle**; non-indexed CUDA lexicographic-min = a different particle (documented, rounding-level). Cross-plane sums: CPU always, CUDA gated — **U10-3**. Row layout 1..14 + anchor 15..18 verified against `pic_cuda.jl:5670-5708` term by term |
| 7 | `_gpic_coupled_moments` 389–400 | `_cuda_gpic_gtuple` cmom 732–735 | `hasproperty` guard on CPU only — **U10-4**. Field order verified independently: `_transport_transverse_moments(cmom, 0)` returns exactly `(varx, cxy, vary)` |
| 8 | `_gpic_drifted_covariance` 405–407, `_gpic_correlation` 411–414, `_gpic_coupled_covariance_resolved` 416–424, `_gpic_cov_pz` 430–432, `_gpic_drifted_gaussian` 435–444, `_gpic_boundary` 446–460, `_gpic_control_variate_mode` 462–473 | **shared**; `_cuda_gpic_boundary` 487 is literally `= _gpic_boundary`; `_gpic_cov_pz` is called from inside a device kernel at 834–835 | none — the rank test, the coupling switch and the `:pic` fallback are one implementation by design |
| 9 | source margin box 607–630 | `_cuda_gpic_augment_prep` 248–256 (indexed); `_cuda_gpic_prepare_interaction` 575–581 (others) | identical formulas (`min(mux − m·sigx)` over both boundaries, marginal sigmas). CUDA adds `do_gauss &&`, which the CPU gets by early-returning at 602 |
| 10 | non-finite chokepoint 632–635, 650–653 | 588–593 (non-indexed); `wf.bounds_host` scan in `_cuda_pic_prepare_interaction_wavefront_indexed!` (indexed) | none observable: an all-NaN particle throws `ArgumentError` on **both** backends and on all three CUDA routes (measured) |
| 11 | field pre-drift + `pz -= ¼(px²+py²)` 640–649 | 791–793 (indexed lk), 854–855 (indexed no-lk), 1190–1193 / 1142–1144 (non-indexed) | none — same order, same expressions, same use of pre-kick momenta |
| 12 | `_pic_interaction_grids` then `_pic_slice_pair_green!` 655–664, margin-enlarged bounds passed to the cache | `_cuda_pic_finish_interaction_indexed` 258–260 then `_cuda_pic_slice_pair_cached_prep!` 304–321 | none — both apply the margin **before** the cache, and the CUDA comment at 299–303 states the contract. Measured parity under `green_cache=:slice_pair` over 4 turns: 5.4e-14 |
| 13 | `_gpic_solve_drifted_field!` 480–528 | `_cuda_gpic_subtract_kernel!` 936–948 + host amp 356–368 / 651–660; `_cuda_gpic_solve_drifted_field!` 1073–1095 (seq) | **the one documented numeric divergence: amp numerator is `qsum` (deposited grid total) on CPU, `N` (slice count) on CUDA.** Measured `(qsum−N)/N ≤ 4.18e-15` |
| 14 | `_gpic_solve_drifted_field_coupled!` 534–577 | `_cuda_gpic_subtract_coupled_kernel!` 950–971 + host 345–354 | none beyond #13: same three outer products, same `sg != 0` guard (CPU 559, CUDA 354), same `amp·(gx·gy + λ·M1·g′ + ½λ²·M2·g″)` |
| 15 | coupled kick branch 707–725 | 812–821 (indexed lk), 870–878 (indexed no-lk) | none: same `cmom`, same `kbb_eff = 2·kbb·½N`, same `S = −s`, same `zL/zR` blend, same discarding of `pz` when `longitudinal_kick=false` |
| 16 | uncoupled kick branch 726–751 | 822–836, 879–883, 1152–1164, 1201–1220 | none: `_gaussian_beambeam_kick_response` (lk) vs `gaussian_beambeam_kick` (no-lk) on both sides — measured **bit-identical** transverse kicks over 360 points, so `longitudinal_kick` does not perturb `px/py` |
| 17 | centroid `pz += ½(Δpx·μ′x + Δpy·μ′y)` 724, 749 | 838 (once, after both branches) and 1219 (inside the `ns≠0` branch) | equivalent: the indexed helper early-returns for `iszero(g.ns)` at 798–810, so line 838 is never reached with `ns == 0` |
| 18 | post-kick re-drift + `pz += ¼(px²+py²)` 752–757 | 839–842, 885–887, 1221–1226 | none |
| 19 | `_gpic_collide!` slice loop 775–820 | `_cuda_gpic_collide_wavefront_indexed!` 118–160, `_cuda_gpic_collide_wavefront!` 502–557, `_cuda_gpic_collide_sequential!` 975–1025 | empty slices skipped on all four (CPU 791; CUDA 269, 548/605, 1000). **`_pic_report_dropped` present in `_pic_collide!`, absent here — U10-2.** CUDA additionally emits timing + green-cache reports |
| 20 | option rejection 778–779 | 78, 87–95, `_cuda_gpic_require_uncoupled` 41–50 (called 505, 978) | correct by design: `cuda_*` are CUDA-only so only CUDA rejects them; measured in §5 |

**Result of the twin diff: no semantic asymmetry that moves a number.** The two
divergences that exist (#6 anchor, #13 amp numerator) are both documented in the
solver docstring at `gaussian_pic.jl:79-85` and both measured at ≤4.2e-15. The
four leads above are an observability defect, a missing guardrail, a cost
asymmetry, and a defensive-shape asymmetry.

---

## 3. Measured CPU↔CUDA parity — the four required cases

Metric: `max_i |a_i − b_i| / max_i|a_i|` per array. Two normalizations are
reported because they answer different questions:

- **coord** — over the six coordinate arrays of both beams (what the existing
  test pins).
- **kick / p_rms** — `max|Δp_CPU − Δp_CUDA|` divided by the beam's momentum
  scale. This is the honest one for `pz`: `Δpz` is a difference of two nearly
  equal `¼(px²+py²)` terms, so normalizing by `max|Δpz|` inflates a
  machine-precision disagreement into ~1e-10 **on every solver in the
  repository**, hybrid or not (see the controls).

Grid 64, TSC unless stated, `longitudinal_kick=true`, 6,000 particles/beam,
5 slices, `green_cache=:none`.

| required case | coord | kick / p_rms | luminosity |
| --- | ---: | ---: | ---: |
| **(a) dead / lost particle present** — one particle with all six coordinates `NaN` (the `ApertureSpec` convention) | *both backends throw* `ArgumentError` | — | — |
| (a′) far outlier particle (survives, stretches the box), flat beam | 5.2e-14 – 1.0e-13 | 2.4e-13 | 3.0e-16 – 2.8e-15 |
| **(b) a slice that is empty** — `equal_width`/9 slices, 7 of 9 empty on beam 1, 5 of 9 on beam 2 | 7.7e-14 – 1.6e-13 | 2.5e-13 – 5.4e-13 | 0 – 5.4e-16 |
| **(c) near-round beam** (σx/σy = 100/95 and 98/96 µm) | 9.2e-15 – 1.3e-14 | 2.06e-13 | 0 – 5.8e-16 |
| **(d) very flat beam** (11:1, and 25:1) | 6.6e-14 – 1.8e-13 | 2.7e-13 – 5.7e-13 | 1.8e-16 – 3.2e-15 |

Coverage inside each case: `{CIC, TSC} × {longitudinal_kick false, true} ×
{indexed wavefront, non-indexed wavefront}`, plus `batch_mode=:sequential`
separately (§5).

**Is 1.8e-13 a lead?** No — the brief's reference band (5.7e-15…1.4e-14) is
reproduced exactly by the *round* case (9.2e-15…1.3e-14). The flat cases are
~10× looser because σy = 9.5 µm makes `py` the worst-conditioned array. Two
controls settle it (`p2_kickbreakdown.jl`, identical configuration):

| solver | e.px | e.py | e.pz | p.px | p.py | p.pz |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| **GaussianPIC**, |Δkick| abs | 1.84e-17 | 5.90e-17 | 6.51e-19 | 1.87e-18 | 3.35e-18 | 8.67e-19 |
| **GaussianPIC**, rel to p_rms | 2.4e-14 | 9.7e-14 | 3.0e-16 | 2.6e-15 | 6.1e-15 | 4.8e-17 |
| **plain PIC** (control), rel to p_rms | 2.0e-14 | **2.4e-13** | 1.0e-16 | 1.4e-15 | 1.9e-14 | 2.4e-17 |
| **soft-Gaussian** (no grid at all), rel to p_rms | 1.3e-14 | 1.3e-14 | 5.0e-17 | 1.2e-15 | 1.8e-15 | 1.2e-20 |

The hybrid is **better than plain PIC** on the worst array (9.7e-14 vs 2.4e-13).
The residual is the shared PIC parallel-reduction order, not this region.

**Docstring claim checked:** `gaussian_pic.jl:79-80` says "measured ~1e-13
relative on the kicks at grid 16". Measured at HEAD: **6.26e-14** at grid 16,
2.99e-13 at grid 64. Claim holds.

**Additional configurations, all clean** (`p10_cache.jl`, flat 11:1, 4 turns
where stated):

| configuration | coord | kick / p_rms |
| --- | ---: | ---: |
| `green_cache=:slice_pair`, 1 turn | 4.29e-14 | 4.76e-14 |
| `green_cache=:slice_pair`, 4 turns | 5.41e-14 | 8.78e-14 |
| `:slice_pair`, 4 turns, `margin_sigma=0` | 1.87e-13 | 3.04e-13 |
| `:slice_pair`, 4 turns, `coupling_tol=0.05` (coupled) | 5.67e-14 | 9.21e-14 |
| `:slice_pair`, 4 turns, growth 0.6 / min_ratio 0.9 | 3.26e-14 | 5.30e-14 |
| `grid_quantize=0.125`, 4 turns | 2.77e-14 | 4.73e-14 |
| `field_derivative=:fourth` | 9.30e-14 | 1.03e-13 |
| `green_type=:standard` | 2.76e-14 | 3.06e-14 |
| `min_transverse_extent=(2e-3,2e-3)` | 1.21e-14 | 1.35e-14 |
| `neutralize=false`, `:slice_pair`, 4 turns | 7.17e-14 | 1.16e-13 |
| `batch_mode=:sequential` (all 4 CIC/TSC × lk combinations) | 8.6e-14 – 1.4e-13 | 9.6e-14 – 1.6e-13 |
| **Float32 reps** | 4.95e-5 = **416 × eps(Float32)** | — |

The Float32 figure is the same eps-multiple as Float64 (1e-13 ≈ 450 ×
eps(Float64)), so precision scales as it should.

**Coupled branch parity** (`coupling_tol = 0.05`, tilt injected into both beams;
the mode census in `p3` confirms all five slices took `:coupled`):

| r_xy | CIC, lk=false | CIC, lk=true | TSC, lk=false | TSC, lk=true |
| ---: | ---: | ---: | ---: | ---: |
| 0.10 | 1.13e-13 | 1.08e-13 | 8.07e-14 | 7.18e-14 |
| 0.30 | 1.25e-13 | 1.29e-13 | 9.58e-14 | 9.93e-14 |
| 0.60 | 2.01e-13 | 1.84e-13 | 1.02e-13 | 1.04e-13 |

**Dead-particle behaviour, stated precisely.** With one particle set to all-NaN,
*both* backends throw `ArgumentError` from the N1 non-finite chokepoint, on all
three CUDA routes, exactly as plain PIC does. On the CPU the throw arrives via
the `mode === :pic` fallback (the NaN makes `bL.sigx` non-finite, so
`_gpic_control_variate_mode` returns `:pic` and `_pic_interaction!`'s own
chokepoint fires); on CUDA it arrives from the bounds scan before the augment.
Different code path, same observable — no divergence, and no silent
continuation on either side.

---

## 4. Independent verification of the total field (hypothesis c)

### 4.1 The derivation, re-derived against the code

Every boxed equation of the theory note was re-derived by hand and matched to
the source:

- **§5 CIC** `g = m₀(xᵢ−h, xᵢ+h) + [m₁(L) − m₁(R)]/h` → `gaussian_pic.jl:192`. ✓
- **§5 TSC** `¾m₀(C) − m₂(C)/h² + 9⁄8[m₀(Lw)+m₀(Rw)] + 3⁄2h[m₁(Lw)−m₁(Rw)] +
  1⁄2h²[m₂(Lw)+m₂(Rw)]` → `gaussian_pic.jl:200-203` (`1.125`, `1.5/h`,
  `0.5/h²`). ✓ The wing polynomials `W₂ = 9⁄8 ∓ 3⁄2(u/h) + ½(u/h)²` were
  expanded from `½(3⁄2 − |u|/h)²` and match the signs used.
- **§7.4 recursion** `c_k = −σ²[(x−µ)^{k−1}G]_A^B + (k−1)σ²c_{k−2}` →
  `_gpic_central_moments` 249–253, all of `c₀..c₄`. ✓
- **binomial shift** `m_k = Σ C(k,j) d^j c_{k−j}` → `_gpic_shift_moments`
  261–265, coefficients (1), (1,1), (1,2,1), (1,3,3,1), (1,4,6,4,1). ✓
- **§7.4 CIC** `W_k = m_k(L) + m_{k+1}(L)/h + m_k(R) − m_{k+1}(R)/h` →
  `_gpic_weighted_moments` 275–277 for k = 0,1,2. ✓ TSC `core`/`wing` at
  283–288 reproduce the §5 weights at every k. ✓
- **§7.4** `M⁽¹⁾ = W₁ − dW₀`, `M⁽²⁾ = W₂ − 2dW₁ + d²W₀` →
  `_gpic_coupled_profiles!` 329–330 with `d = µx − xᵢ`. ✓
- **§7.4 mean derivatives** `g′ = ∫GW′`, `g″ = ∫GW″`; CIC `g′ = [m₀(L)−m₀(R)]/h`,
  `g″ = [G(y−h) − 2G(y) + G(y+h)]/h` → 302–303; TSC `W₂′ = −2u/h²` (core),
  `∓(3⁄2 ∓ u/h)/h` (wings), `W₂″ = −2/h²` (core), `+1/h²` (wings) → 312–316. ✓
  (I checked `W₂′` is continuous at `|u| = h/2` and vanishes at `3h/2`, so no
  delta terms are missing.)
- **§7.2** `λ = σxy/σx²`, `s² = σy² − σxy²/σx²` → `_gpic_boundary` 455–456 as
  `d·(1 − r²)` with the fma'd `muladd(-rxy, rxy, one)` §7.3 prescribes. ✓
- **§7.3** rank test `η > √eps` → `_gpic_coupled_covariance_resolved` 423. ✓
- **§6** `Q̃ᴳ = Qᴳ · ΣQ^part/ΣQᴳ` → `amp = qsum/(sgx·sgy)` at 509. ✓

### 4.2 Measured, against independent references

**Profiles vs 40-node Gauss-Legendre quadrature** of `G·W` (composite, split at
the assignment-function kinks — straddling a kink is a *quadrature* error, and
mis-splitting it initially produced a spurious 2.5e-9 that resolved to 2.4e-14
once fixed; recorded here because it is the kind of probe artefact that gets
mistaken for a defect):

| method | σ, h | max abs error | profile peak |
| --- | --- | ---: | ---: |
| CIC | 1.0, 0.5 | 8.51e-16 | 1.94e-1 |
| CIC | 1.0, 2.0 | 3.33e-16 | 5.86e-1 |
| CIC | 1.0, 0.1 | 6.46e-15 | 6.37e-11 |
| CIC | 0.3, 1.0 | 3.33e-16 | 7.45e-1 |
| TSC | 1.0, 0.5 | 2.43e-14 | 1.92e-1 |
| TSC | 1.0, 2.0 | 4.14e-16 | 5.39e-1 |
| TSC | 1.0, 0.1 | 2.94e-13 | 6.46e-11 |
| TSC | 0.3, 1.0 | 6.66e-16 | 6.54e-1 |

σ→0 limits at a node: CIC → `(0, 4e-10, 1.0, 4e-10, 0)`, TSC → **exactly**
`(0, 0.125, 0.75, 0.125, 0)` — the discrete TSC weights the note predicts.

**Coupled expansion vs brute-force 2D quadrature** of the tilted Gaussian
against the same `W(x)W(y)` (worst node, relative to the peak node):

| r_xy | CIC | TSC | docs §7.5 (CIC) |
| ---: | ---: | ---: | ---: |
| 0.05 | 3.14e-5 | 3.01e-5 | 7.7e-5 |
| 0.20 | 2.11e-3 | 2.03e-3 | 4.6e-3 |
| 0.50 | 4.41e-2 | 4.19e-2 | 1.2e-1 |

Same order and same `O(r³)` growth as the published table (mine normalizes to
the peak node, the note to each node's own value — hence the ~2.5× offset).

**Transport identities:** `|√a − σx| / σx = 0` (exact) and
`|σc² − (d − b²/a)| / |d − b²/a| = 3.15e-16` over five drift distances. So the
subtraction's `sqrt(b.a)` and the analytic kick's transported covariance are the
same quantity, and the `S = −s` convention is consistent between them.

**Neutralization (§6 boxed equation), on a real 40,000-particle deposit through
the shipped `_pic_deposit!`:**

| method | margin | (qsum−N)/N | Σgx·Σgy | residual/N, CPU amp | CUDA amp | no neutralize |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| CIC | 5 | 4.18e-15 | 0.999999801 | **0.0** | 4.18e-15 | 1.99e-7 |
| CIC | 0 | 1.82e-15 | 0.994484048 | **0.0** | 1.82e-15 | 5.52e-3 |
| TSC | 5 | 5.46e-16 | 0.999999794 | **0.0** | 5.46e-16 | 2.06e-7 |
| TSC | 0 | 1.82e-15 | 0.994464343 | **0.0** | 1.82e-15 | 5.54e-3 |

The no-neutralize column reproduces §6's `ε ≈ erfc(m/√2)` prediction (5.5e-3 for
a box wrapping the particles at ≈2.94σ). The CPU convention removes the monopole
**exactly**; the CUDA convention removes it to `(qsum−N)/N`, and this table is
the direct measurement of the docstring's "equal to ~1e-16 whenever no deposit
clips" claim.

**Total field vs a direct O(N²) free-space sum and vs exact Bassetti-Erskine.**
This is the requested independent verification. Source: a 300×300 deterministic
Gaussian quantile lattice (90,000 macroparticles); probes: a 41×41 grid over
±4σ; `px = py = 0` so the drift to both slice boundaries is a no-op and the two
reference Gaussians coincide exactly; `longitudinal_kick = false`; one slice per
beam; run **through the shipped `collide!`**, then divided by `2·kbb` to recover
the PIC-normalized field. Errors normalized by `max|E_direct|`, median (max):

| case | grid | hybrid vs direct | PIC vs direct | **hybrid vs BE** | PIC vs BE | lattice vs BE |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| round 100:100 µm | 48 | 8.68e-4 (4.8e-2) | 1.42e-3 (3.5e-2) | **2.06e-4** (2.2e-3) | 1.13e-3 (1.8e-2) | 1.23e-3 |
| round 100:100 µm | 128 | 4.74e-4 (4.8e-2) | 2.68e-4 (4.6e-2) | **2.06e-4** (3.6e-3) | 5.28e-4 (4.4e-3) | 1.23e-3 |
| flat 106:9.5 µm | 48 | 1.86e-3 (4.3e-2) | 7.11e-3 (4.6e-2) | **3.36e-4** (3.6e-3) | 4.22e-3 (1.6e-2) | 2.49e-3 |
| flat 106:9.5 µm | 128 | 1.03e-3 (4.3e-2) | 1.20e-3 (4.2e-2) | **3.54e-4** (1.2e-2) | 1.17e-3 (1.4e-2) | 2.49e-3 |
| flat 250:9.5 µm | 48 | 4.18e-3 (9.1e-2) | 9.67e-3 (9.0e-2) | **2.96e-4** (4.9e-3) | 5.00e-3 (1.5e-2) | 5.26e-3 |
| flat 250:9.5 µm | 128 | 2.98e-3 (9.1e-2) | 2.48e-3 (9.0e-2) | **4.53e-4** (1.6e-2) | 1.38e-3 (1.8e-2) | 5.26e-3 |

**Reported error of the independent verification: 2.06e-4 (round), 3.4e-4 (11:1),
3.0e-4 (25:1) median relative kick error against the exact Bassetti-Erskine
field, essentially grid-independent.** Compare the theory note §9 table
(1.6e-4 / 2.2e-4 / 2.8e-4 at grid 48; 1.8e-4 / 3.2e-4 at 128, measured with CIC
on a different probe grid): reproduced, from a harness written from scratch for
this audit, going through `collide!` rather than through re-implemented
internals. **This is what pins the ½N_s normalization of §1/§8** — if the
analytic add-back carried `N_s` instead of `½N_s`, or if the residual and the
analytic term were on different scales, this column would be O(1), not 3e-4.

The `hybrid vs direct` column is larger than `hybrid vs BE` and at grid 128 is
not better than plain PIC. That is **not** a defect: the `lattice vs BE` column
shows the discrete quantile lattice itself differs from a continuous Gaussian by
1.2e-3 (round) to 5.3e-3 (25:1), i.e. by more than either solver's grid error.
This is precisely the "shot-noise caveat" of §9 — the hybrid removes the
*systematic* grid bias and does not remove the source's own discreteness — and
the measurement is an independent confirmation of that caveat.

**Margin / neutralize sensitivity** (flat 11:1, grid 128, vs direct):

| margin_sigma | neutralize | hybrid median |
| ---: | --- | ---: |
| 5.0 | true | 1.03e-3 |
| 0.0 | true | 2.32e-3 |
| 5.0 | false | 1.03e-3 |
| 0.0 | false | 2.15e-3 |
| 3.0 | false | 1.91e-3 |
| 6.0 | false | 1.17e-3 |

The margin is worth 2.3× here; neutralization is worth almost nothing *in this
configuration* because the probe beam spans ±4σ, so the interaction box is
already ≈8σ wide and the leak is one-sided (a dipole, which §6 correctly says
neutralization does not remove).

**Analytic add-back anchored to the validated soft-Gaussian kick.** With the
`kbb_eff` scaling the region's own call sites apply (`kick_scale · half_ns · be`,
`gaussian_pic.jl:738-741`), the uncoupled hybrid terms agree with
`_cp_covariance_kick` on the uncoupled `StrongTransverseMoments` at `S = −s` to
**px 3.08e-16, py 4.38e-15, pz 1.18e-14** over 12 (drift, position) pairs. So
the `/4` in `_gpic_cov_pz`, the `rx ≡ 2(cxpx + s·varpx)` convention, and the sign
of `S` are jointly pinned to the independently validated `ThinStrongBeam` path.

**Coupled add-back verified independently of `_cp_covariance_kick`'s own tests.**
A hand-built rotation — diagonalize `[[a,b],[b,d]]`, rotate into the principal
frame, call `gaussian_beambeam_kick(√λ₁, √λ₂)`, rotate back — matches
`_cp_covariance_kick` on the region's `cmom` to **1.4e-16 (px) / 0.0 (py)**.
This also checks the *argument order* of the
`StrongTransverseMoments{T,true}(varx, cxy, vary, cxpx, cxpy, cypx, cypy, varpx,
cpxpy, varpy)` construction that both twins perform — an order error there would
be identical on both backends and invisible to a twin diff.

**Coupled → uncoupled continuity** as `b → 0`: `|Δpx|/px` falls 1.10e-4 →
1.06e-7 and `|Δpy|/py` 1.87e-2 → 1.87e-5 as `r` goes 1e-2 → 1e-5, i.e. linearly.
The two kick branches are mutually continuous.

**Does `longitudinal_kick` perturb the transverse kick?** The region calls
`gaussian_beambeam_kick` when false and `_gaussian_beambeam_kick_response` when
true (`gaussian_pic.jl:728-736`; `gaussian_pic_cuda.jl:823-826` vs `880-881`) —
two different code paths with different internal branch structure. Measured over
360 (σx, σy, x, y) points including the near-round and near-axis branches: the
transverse kicks are **bit-identical** (max relative difference exactly 0.0). No
defect.

---

## 5. Silent option drops (hypothesis d)

Checked from the **declared schema**, not a hand list.

`solver_option_schema(GaussianPICPoissonSolver)` declares **32** options
(29 inherited from `_PIC_SOLVER_OPTION_SCHEMA` + `margin_sigma`, `neutralize`,
`coupling_tol`). Census:

- `solver_configuration`: all 32 present, no omissions (4 extra `resolved_*`
  keys, which are derived echoes, not declarations).
- `configuration_report`: all 32 present. Statuses listed in §1 U10-1.
- **`SolverOptionEffectivenessContract` at HEAD, on this GPU box:**
  `status = passed`, `"every declared solver option reached a runtime consumer
  (68 on CPU, 10 CUDA-only options, 2 launch surfaces)"`. This contract is
  derived from the schema and **fails** an option that has neither a declared
  alternative nor a stated exemption, so it cannot fall behind the schema — it
  is the tripwire Measured Lesson 4 asks for, and it is green.

Reachability of the rejections, measured directly (`p8_routes.jl` §d):

| option | value | CPU | CUDA |
| --- | --- | --- | --- |
| `slice_interpolation` | `:quadratic` | THROW | THROW |
| `interaction_grid` | `:source_slice` | THROW | THROW |
| `grid_extent` | `:sigma` | THROW | THROW |
| `cuda_async` | `false` | no throw | THROW |
| `cuda_batch_fft` | `false` | no throw | THROW |
| `cuda_wavefront_fft` | `false` | no throw | THROW |

(The `cuda_*` trio is CUDA-only, so CPU acceptance is correct and matches the
docstring's "on CUDA" qualifier.)

`coupling_tol` on the two CUDA *reference* routes (`p8_routes.jl` §c):

| route | finite `coupling_tol` |
| --- | --- |
| `batch_mode=:wavefront, cuda_indexed_wavefront=false` | THROW `ArgumentError` |
| `batch_mode=:sequential` | THROW `ArgumentError` |
| `batch_mode=:wavefront, cuda_indexed_wavefront=true` (default) | runs the coupled subtraction |

**No silently dropped option was found.** The part-2 §15 defect ("a mesh-extent
estimator the Gaussian-PIC hybrid silently dropped") is a loud rejection at
`pic_cpu.jl:425-435`, with its measurement note attached. The one residual issue
is that the *report* still calls the rejected options resolved — U10-1.

---

## 6. Clean list — what audits sound, and the evidence

1. **The erf deposition integrals are exact** (theory §5). Verified against
   independent 40-node composite Gauss-Legendre quadrature of `G·W` at four
   (σ, h) regimes per method, including h ≫ σ and h ≪ σ: worst 6.5e-15 (CIC),
   2.9e-13 (TSC), against profile peaks of 1e-1…7e-1. σ→0 gives exactly the
   discrete TSC weights `(⅛, ¾, ⅛)`.
2. **The coupled conditional expansion is the derivation of §7.2/§7.4**, term by
   term (`c_k` recursion, binomial shift, `W_k` combinations, `M⁽¹⁾`/`M⁽²⁾`,
   `g′`/`g″` for both CIC and TSC), and reproduces the published §7.5 accuracy
   table against 2D quadrature: 3.1e-5 / 2.1e-3 / 4.4e-2 at r = 0.05 / 0.20 /
   0.50.
3. **The subtracted Gaussian and the analytic add-back use the same moments.**
   `√(b.a)` equals `b.sigx` *exactly* (0.0 relative), `σc² = d − b²/a` to
   3.15e-16, and both branches carry the same `S = −s` convention into
   `_transport_transverse_moments` and `_cp_covariance_kick`. The subtraction's
   geometry and the kick's geometry are one geometry.
4. **The subtraction is consistent between the field solve and the kick, and the
   ½N_s normalization is correct.** Total field (residual + analytic) vs exact
   Bassetti-Erskine: 2.06e-4 (round), 3.4e-4 (11:1), 3.0e-4 (25:1), essentially
   grid-independent, reproducing the theory note's §9 table from an independent
   harness through the shipped `collide!`.
5. **Neutralization does what §6's boxed equation says.** CPU amp drives the
   residual monopole to exactly 0.0; the leak without it reproduces
   `ε ≈ erfc(m/√2)` (5.5e-3 at a ≈2.94σ box, 2.0e-7 at margin 5).
6. **My own analysis was overturned by measurement, and this is the record of
   it.** I predicted that the coupled branch would under-contain the tilted
   Gaussian, because the box is built from the *marginal* σy while the tilted
   ±m contour extends to `m·σy·(|r| + √(1−r²))` — up to 1.4× at r = 0.6. Direct
   measurement of the actually-subtracted mass refutes it: leak = 9.47e-7 at
   r = 0, 9.44e-7 at 0.1, 7.87e-7 at 0.3, **4.77e-7 at 0.6** — containment
   *improves* with tilt. Reason: the subtraction uses the *conditional*
   `σc = σy√(1−r²)`, which is narrower than σy, and the two correction terms sum
   to ≈0 over the grid because `Σ_j g′_j ≈ Σ_j g″_j ≈ 0`. No lead.
7. **The `sg != 0` (coupled) vs `sgx·sgy > 0` (uncoupled) guard asymmetry noted
   by the previous pass is cosmetic, and now has a structural argument as well
   as a measurement.** `sg = Σgx·Σgy + λΣM1·Σg′ + ½λ²ΣM2·Σg″`, and the last two
   sums vanish to grid-leakage order, so `sg ≈ Σgx·Σgy ≈ 1` structurally.
   Measured 0.99999905…0.99999952 across r = 0…0.6 at margin 5. Both twins use
   the same guard, so it is not a twin divergence.
8. **Both CUDA/CPU divergences that exist are documented and bounded.** The
   anchor choice (§2 row 6) and the amp numerator (§2 row 13, `(qsum−N)/N ≤
   4.18e-15`) are exactly what `gaussian_pic.jl:79-85` claims. The indexed
   route's anchor `idx[1]` is *the same particle* as the CPU's `source.x[1]`.
9. **Empty slices are skipped identically on all four routes**; the probe
   configuration was verified to actually contain empty slices (7 of 9 and 5 of
   9), and parity in that configuration is indistinguishable from the full one.
10. **A dead (all-NaN) particle produces the same observable on both backends**
    — `ArgumentError` from the N1 chokepoint — on all three CUDA routes and
    matching plain PIC.
11. **The batched moment kernel's row layout matches the comment and the CPU
    reconstruction term by term** (rows 1–4 first moments, 5–8 squares, 9–10
    same-plane crosses, 11–14 cross-plane, 15–18 anchor; `nstats = 14 + 4`),
    checked against `pic_cuda.jl:5670-5708` and `_gpic_mom_from_coupled_sums`.
12. **The slice-pair Green cache is applied after the margin augment on both
    backends**, as both files' comments assert; measured parity over four turns
    with the cache live: 5.4e-14.
13. **The region's docstring quantitative claims hold at HEAD.** "~1e-13 at grid
    16" → 6.26e-14. "Use TSC with this solver": hybrid 11:1 grid 64 TSC 3.33e-4
    vs CIC 4.68e-4 (ratio 1.41, the docstring's own ratio); 25:1 TSC 3.03e-4 vs
    CIC 5.07e-4. "For plain PIC TSC is never better than CIC": PIC CIC 2.45e-3
    vs TSC 3.06e-3 (11:1) and 3.06e-3 vs 3.49e-3 (25:1). All confirmed.
14. **`longitudinal_kick` does not perturb the transverse kick**, despite the
    two branches calling different BE routines: bit-identical over 360 points.
15. **Parity is clean under every non-default option combination tried** —
    `green_cache`, `green_type`, `field_derivative`, `grid_quantize`,
    `min_transverse_extent`, `slice_pair_green_growth/min_ratio`,
    `margin_sigma`, `neutralize`, `coupling_tol`, `batch_mode`,
    `cuda_indexed_wavefront`, Float32 — 14 configurations, worst 1.9e-13
    (Float64) and 416 × eps (Float32).

---

## 7. Not checked, and why

- **`interaction_grid = :node` / `:source_slice` and `slice_interpolation =
  :quadratic` behaviour.** Rejected at collide time by design; there is nothing
  to exercise. Verified the rejection instead.
- **Multi-turn dynamics / tune shift / luminosity accumulation.** Out of region
  (task and protocol layer); this unit measured single- and 4-turn collision
  outputs only.
- **The CUDA kernels' internals reached through `pic_cuda.jl`** —
  `_cuda_pic_deposit_drifted_plane!`, `_cuda_pic_interpolate_kick/field`,
  `_cuda_pic_solve_wavefront_fields_*`, `_cuda_pic_force_bounds_indexed_kernel!`,
  the batched-moment reduction, `_cuda_cp_covariance_kick`. Read at the call
  sites and at the `gpic_subtract` injection point (`pic_cuda.jl:2714-2731`,
  `2831-2848`) to confirm the seam contract; their bodies belong to other units.
  Their correctness is nonetheless *bounded* by this unit's measurements: the
  CPU/CUDA parity numbers would not be 1e-13 if any of them disagreed.
- **`_cp_covariance_kick` / Bassetti-Erskine internals** (`strong_beam.jl`).
  Other unit. Used here as an oracle, and independently cross-checked once
  against a hand-built principal-frame rotation (1.4e-16).
- **Performance regression testing.** Only the one targeted measurement in
  U10-3; no benchmark of the production point was run, so no claim is made about
  throughput at HEAD.
- **`grid_extent`-driven dropped-charge behaviour.** Unreachable in this solver
  (rejected); U10-2 records the missing guardrail rather than an active loss.
- **Float32 field-solve accuracy** (as opposed to parity). Measured parity only.

---

## 8. Summary

The Gaussian-subtracted PIC twin pair is **sound**. Every equation in
`docs/theory/gaussian_subtracted_pic_solver.md` that the code implements was
re-derived and then measured against an independent reference: the erf
deposition integrals to 1e-14, the coupled conditional expansion to the
published table, the transport identities exactly, the neutralization identity
exactly, and the assembled field — analytic plus residual — to 2–4e-4 against
exact Bassetti-Erskine, reproducing the theory note's headline accuracy table
from a harness written from scratch and driven through the shipped `collide!`.
CPU↔CUDA parity is at rounding in all four required regimes and in fourteen
further configurations, and the two divergences that exist are the two the
docstring already declares.

The four leads are all Low: an honesty gap in `configuration_report` (U10-1), a
missing dropped-charge guardrail (U10-2), a cost asymmetry where the CPU
computes moments the CUDA twin knows to skip (U10-3), and a defensive-shape
asymmetry in a host helper feeding a device kernel (U10-4), plus one cross-file
seam handed to the auditor (U10-5). None of them moves a number today. This
region continues to be an instance of Measured Lesson 7: the physics core holds,
and what is left sits at the observability and configuration edges.
