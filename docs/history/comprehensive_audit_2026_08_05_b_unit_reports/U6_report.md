# U6 audit report — `src/tasks/strongstrong/pic_cpu.jl` + `src/tasks/strongstrong/slicing.jl`

- **Commit audited:** `7de4d81` (HEAD). Prior audit of this region: `6a3f39ab`, archived as
  `docs/history/comprehensive_audit_2026_08_05_unit_reports/U5_report.md`.
- **Region:** `src/tasks/strongstrong/pic_cpu.jl` (2,005 lines) and
  `src/tasks/strongstrong/slicing.jl` (719 lines), every line.
- **Briefed hypotheses:** (a) thread/chunk-count dependence in reductions — verify the
  count-invariance campaign by measurement above the parallel thresholds; (b) silent
  charge/row loss, box-vs-kick ordering; (c) slicing edge cases and CUDA membership drift.
- **Machine:** Linux, 128 cores, Julia 1.12.4, one NVIDIA RTX 4500 Ada (CUDA probes ran).

## Provenance

**Read (every line, in four passes for `pic_cpu.jl`, one for `slicing.jl`):**
`pic_cpu.jl` 1–700, 700–1359, 1359–2005; `slicing.jl` 1–719.
Read for context only (not part of the region, not reported on except as seams):
`src/tasks/strongstrong/interface.jl` 540–760 (constants, `_PICCPUWorkspace`,
`LongitudinalSlicing`), `src/policies/Policies.jl` 215–260 (`_cpu_worker_count`,
`_run_logical_workers`, `ResolvedCPUExecutionPolicy`), `src/beam/Beam.jl` 325–380
(policy resolution), `src/tasks/strongstrong/spectral.jl` 985–1135,
`src/tasks/strongstrong/gaussian.jl` 55–105,
`src/tasks/strongstrong/pic_cuda.jl` 3940–4030 / 4313–4360 / 4416 / 5220–5560,
`test/runtests.jl` 3134–3300 (Core.Box sweep + thread-invariance pin) and 8682–8760
(dropped-charge testset), `validation/slice_interpolation_emittance_growth.jl`,
`validation/README.md` 540–565, `git diff 6a3f39ab HEAD` over the region.

**Executed (probe scripts, all in session scratch, never in the repository —
`/tmp/claude-320114/-cfs-ad-dxu/37c712a3-734a-4817-a05e-4c9e12cabcef/scratchpad/audit/`):**

| script | what it measures |
| --- | --- |
| `probe1_thread_invariance.jl` | 10 solver configurations, n = 15,000 / 3 slices (5,000 per slice), 1/4/8 workers, bitwise coordinate + luminosity diff; `_slice_transverse_moments` at n = 4095/4096/8192/200000 |
| `probe1b_wide.jl` | same at 1/2/3/5/7/16/64 workers (`--threads=64`) |
| `probe2_thread_invariance_15slices.jl` | n = 90,000 / 15 slices (6,000 per slice), 1/4/8 workers, 6 configurations |
| `probe3_slicing_edges.jl` | slicing edge cases: degenerate z, indivisible n, ns > n, n = 1, ties, live-mask, `_slice_bin` vs boundary-comparison, worker invariance, all-dead/partly-dead |
| `probe4_cuda_membership.jl` | CPU vs CUDA slice membership/boundaries/centers, 44 configurations, on the RTX 4500 |
| `probe5_node_dropped.jl`, `probe5b/5c` | first (synthetic, over-strong-kick) `:node` drop measurement + debugging |
| `probe6_node_dropped_physical.jl` | EIC-like beams from `validation/slice_interpolation_emittance_growth.jl`, one turn, `:node` and `:source_slice` out-of-mesh tally vs the shipped `workspace.dropped` |
| `probe7_control_and_alloc.jl` | luminosity-deposit allocation/time across the 4096 threshold; `:node` staleness **negative control** (stale mesh vs mesh rebuilt at collision time) |
| `probe8_deposit_cost.jl` | serial vs fixed-16-chunk deposit, grid 32/64/128 × n = 4096…200000 × 1/8 workers |
| `probe9_collide_cliff.jl` | end-to-end `_pic_collide!` cost either side of `_PIC_PARALLEL_DEPOSIT_MIN` |
| `probe10_field_inbounds.jl` | `_pic_field!` shipped vs an all-`@inbounds` copy (bit-identity + time) |
| `probe11_deposit_branch.jl` | deposit inner-loop CIC/TSC branch hoisting (hypothesis formed by reading, killed by measurement) |
| `probe12_fix_regressions.jl`, `probe12b.jl` | regression checks of the U5-3/5/6/7/8 and F11 fixes |
| `probe13_f32.jl` | Float32 weight element types |

---

## THE HEADLINE MEASUREMENT — hypothesis (a) verified

**Current constants** (`src/tasks/strongstrong/interface.jl` 566–581):
`_STRONG_STRONG_PARALLEL_MOMENT_MIN = 4096`, `_STRONG_STRONG_PARALLEL_KICK_MIN = 4096`,
`_PIC_PARALLEL_DEPOSIT_MIN = 4096`, `_PIC_DEPOSIT_CHUNKS = 16`, `_REDUCTION_CHUNKS = 64`.

**The claim under test:** "Fixed chunk grids, serial/chunked choice by data size only:
1/4/8 workers bit-identical including spectral luminosity (0 ulp) at zero measured cost;
pin extended above the thresholds."

**Result: the claim holds for this region, at every worker count tested, with one
out-of-region exception (`spectral_t`, LEAD U6-5).**

`probe1`, n = 15,000, 3 `:equal_count` slices → 5,000 per slice (above 4096), grid 16
(grid 64 for the TSC row), 90,000 coordinate values per beam:

```
                     1-vs-4 and 1-vs-8            luminosity
pic                  0/90000 differ, 0 ulp        0 ulp
pic_tsc_g64          0/90000 differ, 0 ulp        0 ulp
pic_slicepair_cache  0/90000 differ, 0 ulp        0 ulp
pic_source_slice     0/90000 differ, 0 ulp        0 ulp
pic_node             0/90000 differ, 0 ulp        0 ulp
pic_quadratic        0/90000 differ, 0 ulp        0 ulp
gpic                 0/90000 differ, 0 ulp        0 ulp
gauss                0/90000 differ, 0 ulp        0 ulp
spectral_l           0/90000 differ, 0 ulp        0 ulp
spectral_t           0/90000 differ, 0 ulp        0 ulp
```

`_slice_transverse_moments` called directly, 1/4/8 workers, `Val(true)` (coupled),
all ten returned moments compared in ulps:

```
n=4095    max moment disagreement over 1/4/8 workers: 0 ulp
n=4096    max moment disagreement over 1/4/8 workers: 0 ulp   (threshold crossing)
n=8192    max moment disagreement over 1/4/8 workers: 0 ulp   (was 131,072 ulp pre-fix)
n=200000  max moment disagreement over 1/4/8 workers: 0 ulp
```

`probe1b`, `--threads=64`, worker counts **1, 2, 3, 5, 7, 16, 64** — every PIC
configuration, `gpic`, `gauss` and `spectral_l`: 0/90000 differ, luminosity 0 ulp at
every pair. (`CPUThreadsExecutionPolicy` refuses a count above `Threads.nthreads`, so
each sweep must be run at a pool ≥ the largest count; the permanent pin's
`unique((1, 2, Threads.nthreads(:default)))` is the reason it only reaches 4 under CI.)

`probe2`, n = 90,000, **15** `:equal_count`/`:equal_area` slices → 6,000 per slice,
grid 32, 540,000 values per beam, 1/4/8 workers: `pic` (both slicings), `pic` with TSC,
`gauss`, `spectral_l` all 0/540000 differ and 0 ulp luminosity. `spectral_t` — see U6-5.

**The pre-fix violations do not reproduce**: the recorded "coordinates ≤ 2.5e-15,
transverse moments to 131,072 ulps" is 0 in every configuration and at every worker
count measured.

**Why it holds, argued from structure (so the pin's envelope is stated, not assumed):**
`_pic_deposit!`/`_pic_deposit_drifted!` (pic_cpu.jl:1338–1365) branch on
`length(x) >= _PIC_PARALLEL_DEPOSIT_MIN` alone; `_slice_transverse_moments`
(slicing.jl:637–638) on `n < _STRONG_STRONG_PARALLEL_MOMENT_MIN` alone. Both chunked
branches use a compile-time-constant chunk count, `_chunk_bounds` depends only on
`(n, nchunks)`, each chunk writes a private accumulator, and the merge is a sequential
chunk-ordered loop. `_run_logical_workers(nchunks)` spawns `nchunks` tasks regardless
of the pool, so the pool size cannot reach the arithmetic. `_pic_cpu_workspace!`'s cache
key (pic_cpu.jl:175) no longer carries the worker count, and `local_charge` is sized by
`_PIC_DEPOSIT_CHUNKS`, so one workspace serves every setting and the
`length(local_charge) == nchunks` fallbacks (1422, 1439) are now dead code.
`slicing.jl` still calls `_cpu_worker_count()` in `_threaded_histogram` (243) and
`_threaded_indices_by_function` (410), and both are invariant *by construction* —
integer counts, and chunk-ordered concatenation of ascending index ranges reproducing
serial ascending order — confirmed by measurement (see Clean list item 3).

---

## Leads

### LEAD U6-1 [Major, confidence high] src/tasks/strongstrong/pic_cpu.jl:608 (also 870–938 and 824)
Claim: under `interaction_grid = :node` and `:source_slice` the dropped-charge tripwire is
structurally unreachable, and in exactly those two modes `grid_extent = :extrema` no longer
implies mesh coverage — so out-of-mesh source charge and un-kicked field particles vanish
with `workspace.dropped[] == 0` and no warning.
Mechanism: both counting calls (`_pic_count_outside_box`, `_pic_count_outside_box_drifted`,
pic_cpu.jl:619 and 632) sit inside `if ge !== :extrema` (line 608), and
`_validate_pic_solver` (lines 234–241) *rejects* any `grid_extent != :extrema` for
`:node`/`:source_slice`. The guard is sound for `:slice_pair`, where the mesh is sized
inside `_pic_interaction!` from this slice's own post-drift extrema, so `:extrema` covers by
construction. It is **not** sound for the other two: `:node` meshes are deliberately built at
**turn start** by `_pic_prebuild_node_caches!` (whose own docstring, line 824, claims "the
zero-weight deposition guard counts any escapee rather than smearing it" — nothing counts it),
and `:source_slice` meshes come from `_pic_union_bounds` computed at the source slice's
*first* use and reused for every later field slice. Both are therefore sized **pre-collision
while the deposits happen after intra-collision kicks** — the identical mechanism the R9
tripwire caught (Measured Lesson 3). `_pic_interaction_node!` (870–938) contains no counting
call of any kind. The suite's `@testset "Dropped PIC charge reaches a reader"`
(test/runtests.jl:8682) exercises only `grid_extent = :sigma` on the default `:slice_pair`
grid, so it cannot see this.
Repro: `probe6_node_dropped_physical.jl` — EIC-like flat pair (parameters lifted verbatim
from `validation/slice_interpolation_emittance_growth.jl`), 30,000 macroparticles per beam,
15 `:normal_quantile` slices, grid 64, CIC, one turn. Instrumented replica of `_pic_collide!`
that changes nothing but adds a tally; the deposits themselves are the shipped
`_pic_solve_drifted_field_with_green_fft!`, and `charge_lost = nsource - sum(workspace.charge)`
agrees with the tally exactly.
```
:node          src outside mesh 2/1800000  charge lost 2.0 particle-charges  shipped workspace.dropped = 0
:source_slice  src outside mesh 1/900000   charge lost 0                     shipped workspace.dropped = 0
```
Negative control (`probe7_control_and_alloc.jl` part B), same run, counting the same source
slices against node meshes **rebuilt from the state at collision time**:
```
source deposits outside the TURN-START mesh:            2 of 1800000
source deposits outside a mesh REBUILT at collision:    0 of 1800000
```
i.e. the escape is caused by intra-turn motion, not by the node-mesh geometry. Expected
after a fix: a non-zero `workspace.dropped[]` and a `@warn` from `_pic_report_dropped` for
the `:node` run, and 0 for the same run at zero kick strength. (Scaling: the synthetic
`probe5_node_dropped.jl` sweep shows the loss growing to 47 % of deposits once the per-turn
transverse excursion exceeds the mesh's 1.5-cell margin, so the magnitude is
kick-strength-dependent, not a fixed small number.)

### LEAD U6-2 [Major (performance), confidence high] src/tasks/strongstrong/pic_cpu.jl:1338–1365 (constants at src/tasks/strongstrong/interface.jl:568, 580)
Claim: `_PIC_PARALLEL_DEPOSIT_MIN = 4096` now selects the fixed 16-chunk deposit far below
its break-even point, making the whole CPU PIC collide ~1.5x more expensive per turn at
**both** 1 and 8 workers; the "at zero measured cost" part of the campaign claim holds only
at the pin's own size (n = 1e6, grid 16).
Mechanism: with the worker-count gate removed, `length(x) >= 4096` alone routes to
`_pic_deposit_threaded!`, whose per-call cost has a **grid-sized, n-independent** term:
16 × `fill!` of a `2nx × 2ny` grid plus 16 × `charge .+= local_grid`. At grid 128 that is
16 × 65,536 × 2 = 2.1 M element touches against 4 touches per particle for CIC. The
threshold is a particle count, so it cannot see the mesh size that sets the break-even.
Before the fix the same path was taken only when `_cpu_worker_count() > 1`, and with
`nchunks = _cpu_worker_count()` — so the 1-worker case is a pure regression and the
8-worker case doubled its fixed overhead (8 → 16 chunks).
Repro: `probe8_deposit_cost.jl` (`_pic_deposit_drifted_serial!` vs the shipped
`_pic_deposit_drifted_threaded!`, same inputs):
```
grid=32   n=4096   w=1  serial 0.040 ms  threaded16 0.223 ms   5.52x slower
grid=64   n=4096   w=1  serial 0.038 ms  threaded16 0.567 ms  14.84x slower
grid=128  n=4096   w=1  serial 0.048 ms  threaded16 1.599 ms  33.06x slower
grid=128  n=4096   w=8  serial 0.048 ms  threaded16 1.448 ms  29.95x slower
grid=128  n=68000  w=1  serial 0.682 ms  threaded16 1.757 ms   2.58x slower
grid=128  n=68000  w=8  serial 0.682 ms  threaded16 1.799 ms   2.64x slower
grid=128  n=200000 w=8  serial 1.755 ms  threaded16 2.317 ms   1.32x slower
grid=32   n=200000 w=8  serial 1.730 ms  threaded16 1.181 ms   0.68x  (finally a win)
```
Break-even is ~40 k particles/slice at grid 32, ~150 k at grid 64, and beyond 200 k at
grid 128 — the threshold is 4,096 everywhere.
End-to-end (`probe9_collide_cliff.jl`, `_pic_collide!`, 15 `:equal_count` slices, per-slice
population straddling the threshold; a **5 % increase in particle count** buys):
```
grid=64   4000/slice w=1  1.078 s/turn (17.96 us/particle)
grid=64   4200/slice w=1  1.614 s/turn (25.62 us/particle)   1.50x / 1.43x per particle
grid=128  4000/slice w=1  4.252 s/turn (70.87 us/particle)
grid=128  4200/slice w=1  6.463 s/turn (102.59 us/particle)  1.52x / 1.45x per particle
grid=128  4200/slice w=8  6.065 s/turn                        (8 workers does not recover it)
```
Expected after a fix (threshold scaled with the mesh, e.g. require
`length(x) >= c * _PIC_DEPOSIT_CHUNKS * nx * ny`): the two rows either side of the
threshold within a few percent of each other per particle.

### LEAD U6-3 [Medium (performance), confidence high] src/tasks/strongstrong/pic_cpu.jl:1990–1991
Claim: the luminosity deposit calls the **workspace-less** `_pic_deposit!`, so above 4,096
particles per slice it allocates 16 fresh `(nx+1) × (ny+1)` matrices on every call — 4.08 MB
per `_pic_luminosity` call at grid 128 — and is 20x slower than the serial path it replaced.
Mechanism: `_pic_luminosity!` reuses `workspace.luminosity_q1/q2` for the accumulators but
then calls `_pic_deposit!(q1, method, x1, y1, xmin, ymin, hx, hy, nx+1, ny+1)`, the 10-argument
method (line 1338), whose threaded branch is `local_charge = [zero(charge) for _ in 1:nchunks]`
(line 1406). The workspace's `local_charge` is sized `2nx × 2ny` for the *interaction* mesh
and is not usable here, so the allocating path is the only one available.
Repro: `probe7_control_and_alloc.jl` part A (`@allocated` on a warmed
`_pic_luminosity(solver, x1, y1, x2, y2, 1.0, ws)`):
```
n/slice=4095   grid=128   0.000 MB per call   0.155 ms/call
n/slice=4096   grid=128   4.082 MB per call   3.050 ms/call      <- one extra particle
n/slice=68000  grid=128   4.082 MB per call  13.391 ms/call
n/slice=68000  grid=64    1.051 MB per call   1.335 ms/call
```
At 15 slices (225 pairs) that is ~0.9 GB of allocation churn per turn at grid 128.
Expected after a fix (a luminosity-sized chunk buffer on the workspace, or the same
mesh-aware threshold as U6-2): 0 MB allocated and the 4095/4096 rows within noise.

### LEAD U6-4 [Low (performance), confidence high] src/tasks/strongstrong/pic_cpu.jl:1843–1858
Claim: `_pic_field!` marks the whole `Ey` pass `@inbounds` but leaves the `Ex` boundary rows
and the **default second-order** `Ex` inner loop bounds-checked; adding `@inbounds` is
bit-identical and 1.22x faster at grid 128.
Mechanism: the `@inbounds` on line 1849 covers only the fourth-order `Ex` inner loop. The
comment at 1819–1824 records the `@inbounds` win as taken ("3.0 us with `@inbounds`"), but the
default `field_derivative = :second` path never gets it. `_validate_pic_grid` already
guarantees `nx, ny >= 5`, which is the safety argument the `Ey` pass relies on.
Repro: `probe10_field_inbounds.jl` (a local copy differing only by `@inbounds`):
```
grid=64   fourth=false  bit-identical=true  shipped  2.90 us  all-@inbounds  2.36 us  1.23x
grid=128  fourth=false  bit-identical=true  shipped 16.20 us  all-@inbounds 13.26 us  1.22x
grid=256  fourth=false  bit-identical=true  shipped 62.41 us  all-@inbounds 57.32 us  1.09x
grid=128  fourth=true   bit-identical=true  shipped 17.95 us  all-@inbounds 17.64 us  1.02x
```

### LEAD U6-5 [Low, confidence high, OUT OF REGION — cross-file seam] src/tasks/strongstrong/spectral.jl:1000 and 1043–1062
Claim: the campaign's "including spectral luminosity (0 ulp)" is true of the **longitudinal**
spectral solver only. The **transverse** solver's luminosity is still worker-count dependent,
because `_spectral_collide_transverse!` chunks by `clamp(_cpu_worker_count(), 1, max(n1, n2))`
and folds `sum(lum_parts)` over that many partials.
Mechanism: coordinates are safe — each field particle's kicks accumulate in a fixed source
order regardless of chunking — but `lum_parts` is a per-chunk float partial-sum vector whose
*length* is the worker count, so `sum(lum_parts)` reassociates when the worker count changes.
The permanent pin cannot see it: the above-threshold block (test/runtests.jl:3262) omits
`spectral_t` entirely, and the sub-threshold block compares it with
`isapprox(...; rtol = 8 * eps(Float64))`, which absorbs the difference.
Repro: `probe2_thread_invariance_15slices.jl`, `SpectralPoissonSolver(longitudinal_kick=false)`,
n = 90,000, 15 slices, 1/4/8 workers:
```
spectral_t 1-vs-4  coordinates 0/540000 differ   lum 1 ulp (2.1622792634970486e18 vs …483e18)
spectral_t 1-vs-8  coordinates 0/540000 differ   lum 2 ulp (2.1622792634970486e18 vs …481e18)
```
(also 1 ulp at 1-vs-2 with 3 slices, `probe1b_wide.jl`). Expected after a fix
(`_REDUCTION_CHUNKS`-style fixed chunk grid, matching what `pic_cpu.jl`/`slicing.jl`/
`gaussian.jl` already do): 0 ulp. Reported and stopped here per the seam rule — the fix is
in `spectral.jl`, not my region.

### LEAD U6-6 [Low, out-of-hypothesis, confidence med, cross-file seam] src/tasks/strongstrong/pic_cpu.jl:1551–1568
Claim: `_pic_tsc_weights` still computes its weights from untyped `Float64` literals, so a
`Float32` beam gets `Float64` TSC weights on CPU while the CUDA twin computes them in
`Float32` — a backend divergence in a deposit the 2026-08-05 audit (U2-3) explicitly aligned
in closed form.
Mechanism: `0.125 + 0.5 * (t - f)` with `f::Float32` promotes to `Float64`;
`_cuda_pic_tsc_weights` (pic_cuda.jl:4329–4357) writes every literal as `typeof(u)(…)`. The CIC
pair is already type-clean on both sides (`zero(u)`, `one(f)`), so only TSC diverges. The CPU
then accumulates `Float32_array += Float64_product`, i.e. in Float64 with a final rounding,
where the device accumulates in Float32.
Repro: `probe13_f32.jl`
```
_pic_tsc_weights(3.3f0, 16) -> eltype(w) = Float64      (CUDA twin: Float32)
_pic_cic_weights(3.3f0, 16) -> eltype(w) = Float32      (matches)
```
Expected after a fix: `Float32`. Flagged rather than pursued because measuring the end-to-end
Float32 CPU/CUDA PIC divergence is a parity-contract job outside this region.

### LEAD U6-7 [Low, out-of-hypothesis, confidence high, cross-file seam] src/tasks/strongstrong/slicing.jl:220–240 (`_live_z_stats`) and :464–498 (`_finish_longitudinal_slices` centroid)
Claim: slice **membership** is identical CPU vs CUDA in every case I could construct (see
Clean list item 11 — open lead U2-2 does not reproduce), but the **boundaries** and **centers**
are not bit-identical across backends: `:normal_quantile` / `:specified` boundaries differ by
up to 1,363 ulps and `:equal_count` centers by up to 48,247 ulps.
Mechanism: `_live_z_stats` computes `μ` and `σ` with a serial accumulation loop while
`_cuda_live_z_stats` uses device reductions, so the quantile boundaries `μ + σq` differ in the
last bits; and `_finish_longitudinal_slices` computes the centroid as `sum(i -> z[i], idx)`
where `_cuda_slices_from_indices` uses `sum(@view z_host[hidx])` — different pairwise-reduction
shapes on the same host data. Boundaries and centers feed the drift distances
`sL/sR = (center − boundary)/2` directly, so this is a real (if tiny: ~1e-16 absolute here)
backend divergence upstream of every kick, and it is *upstream* of the membership comparison
that currently passes.
Repro: `probe4_cuda_membership.jl` (RTX 4500, 44 configurations). Representative rows:
```
n=200000 continuous  normal_quantile ns=7   membership_diff=0  bnd=  29 ulp  ctr= 48 ulp
n=200000 quantized   normal_quantile ns=15  membership_diff=0  bnd=1294 ulp  ctr=126 ulp
n=200000 continuous  equal_count ns=7       membership_diff=0  bnd=   0 ulp  ctr=48247 ulp
n=200000 continuous  equal_area ns=15       membership_diff=0  bnd=   0 ulp  ctr=  4 ulp
```
Expected after a fix (or after a decision that it is acceptable): a stated tolerance in the
parity contract. `:equal_area` and `:equal_count` boundaries are already 0 ulp, so the
divergence is confined to the moment-derived methods and the centroid reduction.

### LEAD U6-8 [Low, out-of-hypothesis, confidence high] src/tasks/strongstrong/slicing.jl:388
Claim: the comment "One convention, slice 1, everywhere (audit part 6, R7)" is false for
`:equal_count`, which files a zero-width beam into the **last** slices by rank.
Mechanism: `_longitudinal_slices_equal_count` never reaches `_slices_from_boundaries`; it
builds membership from the rank permutation and calls `_finish_longitudinal_slices` directly,
so the degenerate-boundary branch at 389–395 does not apply to it. This is *deliberate* —
it is the documented R2 rank contract in `LongitudinalSlicing`'s docstring — and both backends
agree, so it is a documentation-accuracy lead, not a behavioural defect. The word "everywhere"
is the problem.
Repro: `probe3_slicing_edges.jl` section (c1)/(c4):
```
all 7 particles at one z, ns=3:  equal_area/equal_width/normal_quantile/specified -> [7,0,0]
                                 equal_count                                      -> [2,2,3]
single particle, ns=3:           every other method -> [1,0,0]   equal_count -> [0,0,1]
```
CUDA agrees in both cases (`probe4`, membership_diff = 0). Expected after a fix: the comment
names `:equal_count` as the rank-contract exception.

### LEAD U6-9 [Low, out-of-hypothesis, confidence high] src/tasks/strongstrong/pic_cpu.jl:1243–1247
Claim: two unreachable branches in `_pic_align_grid_origins`.
Mechanism: `f1, f2 ∈ [0, 1)` by construction (`v/h − floor(v/h)`), so `t = (f2 − f1)/2 ∈
(−0.5, 0.5)` and neither `t > 0.5` nor `t < −0.5` can hold. The intent (wrap the shift into
half a cell) is already satisfied; the algebra that matters — post-shift fractional separation
exactly 0 for non-`:standard`, exactly ±0.5 for `:standard` — is correct either way.
Repro: read the definitions of `f1`/`f2` at lines 1237–1238; or evaluate
`Octopus._pic_align_grid_origins(:lattice, s0, f0, h)` over any grid of `(s0, f0, h)` and
observe that `((f0−shift)/h − floor(…)) − ((s0+shift)/h − floor(…))` is always ~0 without the
branches ever firing.

### LEAD U6-10 [Low, out-of-hypothesis, confidence high] src/tasks/strongstrong/pic_cpu.jl:1418–1440
Claim: the `length(local_charge) == nchunks` fallbacks are dead code, and the two of them
disagree about what to fall back to.
Mechanism: `_pic_cpu_workspace` always builds `local_charge` with exactly
`_PIC_DEPOSIT_CHUNKS` entries (interface.jl:637) and both threaded functions compare against
the same constant, so the guards can never fire. If they ever could, line 1422 falls back to
the *allocating threaded* path while line 1439 falls back to *serial* — two different numeric
results for the same failure. Noted by the prior unit report as an inconsistency; the removal
of the worker count from the workspace cache key has now made both unreachable rather than
fixing the inconsistency.
Repro: `Octopus._pic_cpu_workspace(Float64, 16, 16).local_charge |> length` == 16 ==
`Octopus._PIC_DEPOSIT_CHUNKS`; no call site constructs a `_PICCPUWorkspace` any other way
(`grep -n "_PICCPUWorkspace{T}(" src/`).

---

## Clean list — what audits sound, and the evidence

1. **Worker-count invariance of every reduction in this region.** Measured 0 ulp at
   1/2/3/4/5/7/8/16/64 workers over 10 solver configurations, two slice counts, two
   population sizes and 90,000–540,000 coordinate values per comparison
   (`probe1`, `probe1b`, `probe2`). `_slice_transverse_moments` 0 ulp at n = 4095, 4096,
   8192, 200000 — the threshold crossing and 50x above it.
2. **The fixed-chunk structure that makes it hold**, read and argued line by line:
   `_PIC_DEPOSIT_CHUNKS`/`_REDUCTION_CHUNKS` are `const`; the serial/chunked branch reads
   only `length(x)`/`n`; `_chunk_bounds` (slicing.jl:458) is a pure function of
   `(n, nchunks, chunk)` and its `fld` partition covers `1:n` exactly once (verified by hand
   for n = 3, nchunks = 8: chunks 3, 6, 8 take indices 1, 2, 3 and the rest are empty);
   the merges at pic_cpu.jl:1412, 1429, 1449 and slicing.jl:675 are sequential and
   chunk-ordered; `_pic_cpu_workspace!`'s key (pic_cpu.jl:175) is worker-count free.
3. **`_threaded_histogram` and `_threaded_indices_by_function` remain invariant despite
   still chunking by `_cpu_worker_count()`.** Histogram counts are `Int` (associative);
   index lists are chunk-ordered concatenations of ascending ranges, which reproduce the
   serial ascending order exactly. Measured (`probe3` (c8), n = 200,000, ns = 15, 1/4/8
   workers): `equal_area`, `equal_width`, `equal_count`, `normal_quantile` all give
   identical `indices`, bit-identical `boundary`, bit-identical `center`.
4. **F5 (`chunk_counts` name-collision) fix intact** — slicing.jl:264–273 uses the distinct
   name, and the suite's lowered-code `Core.Box` sweep (test/runtests.jl:3134) still guards it
   with `_spectral_collide_longitudinal!` as the single argued exception.
5. **U5-7 (CIC top-edge) fixed, and the CUDA twin kept in step.** `probe12`:
   `_pic_cic_weights(4.0, 5) = (4, (0.0, 1.0))`, `_pic_cic_weights(31.0, 32) = (31, (0,1))`;
   single-particle deposit centre of mass equals `u` at both u = 2 (interior control) and
   u = 4 (the boundary case that used to report 3.0). Interior values unchanged
   (`u = 3.5 → (0.5, 0.5)`). `_cuda_pic_cic_weights` (pic_cuda.jl:4313–4327) carries the same
   `u − (base − 1)` form and cites U5-7.
6. **U5-5/U5-6 (dropped counter) fixed for `:slice_pair`.** `probe12`: a corner escapee present
   in *both* the source and the field sets gives `dropped == 2` (one per particle, not per
   axis); a source-only escapee gives `dropped == 1` with deposited charge 4000 of 4001, i.e.
   the counter and the missing charge agree exactly. The suite pins the same at
   test/runtests.jl:8682–8760.
7. **U5-8 (luminosity overlap extent) fixed.** `probe12b`, 200 uniformly spaced particles,
   grid 16: TSC deposits 0.494521 of 200 particle-charges (0.247 %) into the previously
   excluded row/column, worth a 6.94e-5 relative luminosity deficit under the old
   `1:nx, 1:ny` sum; CIC deposits exactly 0 there and the old/new sums differ by 1.76e-16
   (reassociation only). The CUDA overlap kernels were extended in the same campaign
   (pic_cuda.jl:2426–2428, 3584, 3661).
8. **U5-3 / F11 (silently-ignored configuration) fixed, verified by enumeration.** `probe12`:
   `:node` + `:quadratic` throws; `:node` + `:linear` does not; `:node` + `grid_extent=:sigma`
   throws; and over the seven CUDA route combinations, `:node` is accepted **only** for
   `(:wavefront, async, batch_fft, wavefront_fft, indexed)` all true and for
   `(:sequential, async=false)`, throwing for every single-flag deviation.
9. **Deposit/interpolation index safety and the out-of-range contract.** CIC `base ∈ [1, n−1]`
   → nodes up to `n`; TSC `base ∈ [1, n−2]` → nodes up to `n`; the luminosity mesh is
   `(nx+1) × (ny+1)` with `u_max = nx − 1.05`, so TSC's `floor(u)+2 = nx+1` is the last
   index and it exists. Out-of-range and non-finite input take the zero-weight branch
   (`!(0 <= u <= n−1)` is false for NaN in both comparisons), so a dropped particle writes
   zeros at index 1 rather than throwing or smearing.
10. **Box-vs-kick ordering in `_pic_interaction!` (hypothesis (b), the `:slice_pair` path).**
    Read line by line: the field box (571–584) is accumulated *inside* the loop that applies
    the drift at 566–567, i.e. from post-drift coordinates; the source box (534–537) uses the
    same `x + px*sL` / `x + px*sR` values the deposits bin; the dropped counts (619, 632) are
    taken against `source_grid`/`field_grid` *after* `_pic_slice_pair_green!` may have enlarged
    them (605), which is the mesh actually used. So `:extrema` covers by construction here,
    and skipping the count is correct — this is precisely the property that fails in the other
    two modes (LEAD U6-1).
11. **CPU/CUDA slice membership — open lead U2-2 does not reproduce.**
    `probe4_cuda_membership.jl` on the RTX 4500, 44 configurations
    (n ∈ {777, 2000, 200000} × quantized/continuous × 5 methods × ns ∈ {3, 7, 15}, plus
    degenerate z and ns > n): **membership_diff = 0 in every one**, and no particle is left
    unassigned on either backend. `:equal_area` and `:equal_count` boundaries are 0 ulp.
    Separately, CPU `_slice_bin`'s division-and-clamp rule agrees with the boundary-comparison
    rule the CUDA `:equal_width` path uses on 0 of 404,000 sampled particles (`probe3` (c7)).
    (The residual boundary/centre ulp divergence is LEAD U6-7.)
12. **Slicing edge cases (`probe3`).** Degenerate z (all 7 particles at one z): weights sum to
    1 exactly, boundaries all equal, centers finite, slice 1 for every method except the
    documented `:equal_count` rank split. n = 10 / ns = 3: `[3,4,3]`, `[3,3,4]`, `[3,3,4]`,
    `[4,2,4]`, `[4,2,4]`, `Σw − 1 = 0` exactly in all five. ns = 7 > n = 3: empty slices
    handled, `Σw − 1 = 0`, boundaries sorted, centers finite. n = 1: handled. All-dead beam
    under `allow_lost_particles`: throws `ArgumentError`. Partly dead (1 NaN of 4): the dead
    one joins no slice and `Σw − 1 = 0`.
13. **The `:equal_count` ties contract still matches its docstring, to the number.** 2,000
    particles quantized to 64 z levels: counts are exactly equal
    (`[500,500,500,500]`, `[400×5]`, `[222,222,222,222,223,222,222,222,223]`), `Σw − 1 = 0`,
    and at ns = 9 exactly **238** particles sit outside the half-open `[lb, rb)` interval of
    their own slice — the number the `LongitudinalSlicing` docstring quotes ("measured at 238
    of 2000 particles for z quantized to 64 levels"). Membership is also identical whether the
    live mask is off (`sortperm(z)`) or on (`sort!(findall(flags); by = i -> z[i])`), so the
    two tie-ordering paths agree.
14. **`_pic_field!` stencils re-derived term by term** (second-order interior
    `(φ[i−1] − φ[i+1])/2h`; fourth-order `[(φ[i+2] − φ[i−2]) + 8(φ[i−1] − φ[i+1])]/12h`;
    one-sided `(1.5φ₁ − 2φ₂ + 0.5φ₃)/h` and its mirror), all equal to `−∇φ`; `nx, ny ≥ 5` from
    `_validate_pic_grid` makes every boundary index safe; the column-major loop order is
    correct in both passes.
15. **`_pic_align_grid_origins` algebra re-derived**: for non-`:standard` the post-shift
    fractional separation is `(f2 − t) − (f1 + t) = 0` exactly; for `:standard` the `∓0.25`
    makes it exactly ±0.5, which is the half-cell offset that keeps the kernel off its own
    singularity. `_pic_green_lattice!`'s 1e-6-cell integer-separation check still throws rather
    than rounding.
16. **A performance hypothesis formed by reading and then killed by measurement.** The
    `Symbol(method) == :CIC` branch sits *inside* the per-particle deposit loop and makes the
    typed IR union-valued (13 `Union{`, 4 `::Any`). Hoisting it out of the loop gives
    **1.00x** (`probe11_deposit_branch.jl`: 12 grid/method/n combinations, ratios 0.95–1.07x,
    outputs bit-identical). Julia's union splitting already handles it; the branch costs
    nothing and should be left alone.

---

## Not checked, and why

- **Multi-turn growth of the LEAD U6-1 silent loss.** Measured for one turn at EIC-like
  parameters (2 of 1.8 M deposits). The node cache is rebuilt every turn, so the loss does not
  accumulate mechanically, but its size tracks the per-turn transverse excursion and I did not
  run a 600-turn emittance-growth study to see how it evolves as the beam blows up.
- **End-to-end Float32 CPU-vs-CUDA PIC parity** (LEAD U6-6). I established the element-type
  divergence; quantifying the resulting coordinate difference is a parity-contract measurement
  spanning `pic_cuda.jl` and the contract runner, outside this region.
- **`:lattice` Green table under `ForwardDiff.Dual` `rho`.** The prior unit report flagged that
  `_pic_lattice_rho_key` calls `Float64(rho)` and the cache is `Matrix{Float64}`; the code is
  unchanged at HEAD and I did not build the AD probe. Still an open observation.
- **CUDA PIC collide numerical parity end-to-end.** A GPU was available and I used it only for
  the slicing-membership comparison that hypothesis (c) named. The device kernels are U-other's
  region.
- **`_STRONG_STRONG_PARALLEL_KICK_MIN`** is consumed by `gaussian.jl:70`, not by my region;
  whether 4096 is the right threshold there is the same question as LEAD U6-2 but for a
  64-chunk × 10-element reduction (whose fixed overhead is negligible), so I did not measure it.
- **The full CI gate** (`Pkg.test(julia_args=["--threads=4"])`) was not run: a reading unit does
  not modify the repository and the gate belongs to the orchestrator. Every number above comes
  from a scratch probe against the unmodified library.
