# U1 report — `src/tasks/strongstrong/pic_cuda.jl` lines 1–2000

Repo: `/cfs/ad/dxu/Library/Julia/Octopus` @ `7de4d81`. Read-only audit; **no repository file
was modified**. GPU probes were run on the local NVIDIA RTX 4500 Ada (driver 580.119.02,
CUDA 13.0); every probe script lives in the session scratchpad
`/tmp/claude-320114/-cfs-ad-dxu/37c712a3-734a-4817-a05e-4c9e12cabcef/scratchpad/audit/`.

## Provenance

**Read in full, line by line:** `src/tasks/strongstrong/pic_cuda.jl` 1–2017 (the assignment
range is 1–2000; the containing device function `_cuda_pic_apply_indexed_node_kick!` ends at
2017 and was read to its `end` so the kick arithmetic could be compared to the CPU twin).

**Read out of region, only to validate a claim made *about* my region** (each is another
unit's territory; nothing below is reported as a finding against those lines):
pic_cuda.jl 2020–2064 (indexed node kick launcher/kernel that consumes the region's plane
layout), 2084–2130, 2133–2226 (slice-pair Green cache predicates), 2276–2408
(`_cuda_pic_solve_*field*` — checked for aliasing of `phi` with the shared charge buffer),
2410–2565 (wavefront workspace allocation/sizing that the region's launches index into),
2582 (node plane layout docstring), 3510–3743 (`_cuda_pic_wavefront_luminosity*`,
`_cuda_pic_luminosity` — the region's luminosity callees), 3745–3820 (gather/scatter
kernels), 4162–4305 (bounds reduce helpers + the four bounds kernels the region launches),
4313–4360 (CIC/TSC weights), 4875–4971 (`_cuda_pic_interpolate_field`,
`_cuda_pic_kick_node_kernel!`), 4973–5100, 5654–5680, 5743–5761, 5820–6009 (fused Gaussian
moment/kick kernels launched from region lines 1200–1218).

**CPU twin read:** `src/tasks/strongstrong/pic_cpu.jl` 1–260 (collide, validation),
304–460 (`_pic_union_bounds`, `_require_cuda_pic_options`, kbb/luminosity scales),
459–710 (`_pic_interaction!` — the reference for `_cuda_pic_prepare_interaction` and the
kick), 711–948 (`_pic_build_node_grids!`, `_pic_prebuild_node_caches!`,
`_pic_interaction_node!`, `_slice_interpolation_parameters`), 974–1101
(`_pic_axis_extent`, `_pic_interaction_grids`), 1103–1260 (Green cache, expand, realign),
1863–2004 (`_pic_interpolate_kick`, `_pic_interpolate_kick_quadratic`, `_pic_luminosity!`).

**Also read:** `src/tasks/strongstrong/interface.jl` 72–95, 209–330, 1114–1135, 1195–1300,
1428–1495, 2303–2315; `src/contracts/Contracts.jl` 99–135, 525–560, 760–930, 1023–1070;
`src/policies/Policies.jl` 259–280; `AGENTS.md` "Hard-Won Rules";
`docs/comprehensive_audit.md` "Measured Lessons"; prior unit report
`docs/history/comprehensive_audit_2026_08_05_unit_reports/U1_report.md`;
`git diff 6a3f39ab..HEAD -- src/tasks/strongstrong/pic_cuda.jl` (99 insertions, 56 deletions;
three hunks land inside my region — lines 217–235, 594–605, 671–696).

**Executed (GPU):**
- `probe_sink.jl` — per-pair luminosity sink population across 8 CPU/CUDA route
  combinations. **Ran; lead confirmed.**
- `probe_routes.jl` — `:node` route gates, `:node`+`:quadratic` rejection, CUDA run-to-run
  bitwise reproducibility, `pic_timing_detail` route-swap effect, node CPU/CUDA agreement
  on both honoured routes. **Ran.**
- `probe_node_detail_gate.jl` — the F11 runtime gate at pic_cuda.jl:220 and whether it
  aborts before mutating the beam. **Ran.**

---

## Leads

### LEAD U1-1 [Medium, confidence high] src/tasks/strongstrong/pic_cuda.jl:156-160, 360-366, 728-830, 832-926, 928-1055

Claim: the per-pair luminosity sink `_ACTIVE_PIC_LUMINOSITY_PAIR_SINK` is populated by the
CUDA backend on **one** of its six routes, while the CPU twin populates it on every route —
so the sink returns silently empty on the CUDA sequential and non-indexed-wavefront routes,
and the backend-consistency contract's per-pair comparison is disarmed by construction for
`batch_mode = :sequential`.

Mechanism: the CPU `_pic_collide!` pushes one `(turn, i, j, luminosity)` record per slice
pair unconditionally (pic_cpu.jl:114–118), inside the single collision loop that serves
every configuration. On CUDA the push exists only inside
`_cuda_pic_wavefront_luminosity_indexed` (pic_cuda.jl:3672–3685), which is reachable only
from the fully-indexed wavefront sub-route (region lines 267–282 and 1410–1413). The
region's other five luminosity producers — sequential non-async (158), sequential node
(158), `_cuda_pic_interaction_pair_async!` (810), `_cuda_pic_interaction_pair_batched_fft!`
(893) and `_cuda_pic_interaction_wavefront_batched_fft!` (979, via
`_cuda_pic_wavefront_luminosity`/`_cuda_pic_wavefront_luminosity_batched`) — return only the
scalar sum and never touch the sink. Nothing warns. This is the "loud beats silent" rule
(AGENTS.md) applied to a diagnostic surface, plus a CPU/CUDA twin divergence. The
downstream consequence is the "correct check, never executed" class:
`StrongStrongPICBackendConsistencyContract` gates its whole per-pair comparison on
`pair_trace_expected = contract.batch_mode == :wavefront` (Contracts.jl:867–874), so with
`batch_mode = :sequential` the check reports
`slice_pair_luminosity_records_compared = 0` and `passed = true` having compared nothing.
Every contract instantiated today uses the `:wavefront` default (Contracts.jl:130, 537,
2493; runtests.jl:3786; validation/strong_strong_pic_cache_backend_consistency.jl:42), so
the disarmed branch is *latent*, not currently active — but the CUDA sequential route has no
per-pair luminosity coverage at all.

Repro (measured, `scratchpad/audit/probe_sink.jl`; 4 slices → 16 pairs, n=4000/beam):

    julia --startup-file=no --project=. scratchpad/audit/probe_sink.jl

expected/observed output — the number after `sink_records=` is the count of records pushed
into a scoped `_ACTIVE_PIC_LUMINOSITY_PAIR_SINK`:

    CPU  sequential (default flags)          lum=5.756043461949609e14  sink_records=16
    CPU  wavefront                           lum=5.756043461949609e14  sink_records=16
    CUDA sequential cuda_async=false         lum=5.756043461949625e14  sink_records=0
    CUDA sequential cuda_async=true          lum=5.756043461949615e14  sink_records=0
    CUDA wavefront full indexed (default)    lum=5.756043461949622e14  sink_records=16
    CUDA wavefront indexed=false             lum=5.756043461949628e14  sink_records=0
    CUDA wavefront wavefront_fft=false       lum=5.756043461949628e14  sink_records=0
    CUDA wavefront async=false               lum=5.756043461949618e14  sink_records=0

The durable identity: install `_ACTIVE_PIC_LUMINOSITY_PAIR_SINK` around a CUDA PIC
`collide!` on any route other than `batch_mode=:wavefront` with all four cuda_* flags true;
the sink must contain `nslices1 * nslices2` records (16 here) and contains 0.

---

### LEAD U1-2 [Low, confidence high] src/tasks/strongstrong/pic_cuda.jl:585-605

Claim: the U1-3 fix that landed in this diff copied three of the four fields the CUDA
workspace key was missing relative to its CPU twin; `Symbol(solver.interaction_grid)` is
still absent, so two solvers differing only in `interaction_grid` share one workspace under
the same task label.

Mechanism: the CPU key is
`(:cpu_pic_green_cache, label, T, grid, green_type, green_cache, min_ratio, growth,
interaction_grid)` (pic_cpu.jl:183–193). The CUDA key (585–605) now carries `green_cache`,
`slice_pair_green_min_ratio` and `slice_pair_green_growth` — added by this diff with the
comment "the CPU key carries them and this one did not" — but not `interaction_grid`. The
consequence is inert **today**: on CUDA the `:node` route never writes
`workspace.slice_pair_green_cache` (the node routes at 130–149 and 1349–1452 use the node
mesh caches instead), and `_cuda_pic_wavefront_workspace!`/`_cuda_pic_wavefront_node_workspace!`
keep `:standard` and `:node` entries under separate cache keys, so no cross-mode entry can
be served. It is a completeness defect in a fix whose own rationale is "the CPU key carries
it": the next mode that both keys the cache and differs by `interaction_grid` inherits the
original U1-3 reproducibility drift.

Repro (static, survives line drift):

    grep -n "solver.interaction_grid" src/tasks/strongstrong/pic_cpu.jl   # in the CPU key
    sed -n '/function _cuda_pic_workspace!/,/^        end$/p' src/tasks/strongstrong/pic_cuda.jl

The CUDA key must list `Symbol(solver.interaction_grid)` and does not.

---

### LEAD U1-3 [Low, confidence high] src/tasks/strongstrong/pic_cuda.jl:1587

Claim: `_cuda_pic_prepare_interaction_wavefront_indexed!` hardcodes `threads = 256` — the
only kernel launch in the whole 6009-line file that bypasses `_cuda_pic_threads(family)` —
so the public `CUDAPICLaunchConfig` surface, the device `MAX_THREADS_PER_BLOCK` validation
and the `:cuda_pic_launch` receipt stream all skip the production route's bounds reduction.

Mechanism: `_cuda_pic_threads` (interface.jl:287–295) is the single point that reads the
resolved launch configuration *and* the single emitter of `:cuda_pic_launch` receipts
(line 293); `_resolve_cuda_pic_configuration` validates each family against the device
maximum by iterating `_CUDA_PIC_LAUNCH_FAMILIES` (interface.jl:209–214). Line 1587's literal
`256` feeds four launches — `_cuda_pic_init_wavefront_bounds_partials_kernel!` (1592),
`_cuda_pic_force_luminosity_bounds_indexed_kernel!` (1607, 1612) and
`_cuda_pic_force_bounds_indexed_kernel!` (1618, 1623) — none of which therefore appear in the
receipts a user reads to confirm their configuration took effect. There is no correctness
consequence at present (256 is a legal block size on every CUDA device, and
`_cuda_pic_bounds_block_reduce`'s `CuStaticSharedArray(T, (N, 32))` is sized for up to 1024
threads), but this is exactly the S1/S18 shape the previous audit priced twice: a public
tuning surface that does not reach a consumer, in the hottest prepare stage of the default
route.

Repro (static):

    awk 'NR<=2000' src/tasks/strongstrong/pic_cuda.jl | grep -n "threads *= *[0-9]"

must return nothing (every launch resolved through `_cuda_pic_threads`); it returns exactly
one hit, `1587:            threads = 256`.

---

### LEAD U1-4 [Low, confidence med] src/tasks/strongstrong/pic_cuda.jl:16-21

Claim: `collide!(solver, beam1, beam2, CUDABackend, ctx::TrackingContext)` accepts a real
`TrackingContext` but never installs `_ACTIVE_PIC_TIMING_CONTEXT`, so the per-pair
luminosity records the CUDA indexed route emits are stamped `turn = -1` while the CPU twin
given the same `ctx` stamps `ctx.turn`.

Mechanism: only `_strong_strong_collide!` (region lines 23–33) wraps the collide in
`Base.ScopedValues.with(_ACTIVE_PIC_TIMING_CONTEXT => (label=..., turn=ctx.turn))`. The
sink writer reads that scoped value, not the `ctx` argument
(`turn = context === nothing ? -1 : context.turn`, pic_cuda.jl:3675–3676), whereas the CPU
writer reads `ctx` directly (`turn = ctx === nothing ? -1 : ctx.turn`, pic_cpu.jl:116). The
three-argument `ctx::TrackingContext` entry point at 16–21 threads `ctx` only far enough to
gate `_pic_compute_luminosity`. Any consumer that keys records by turn — the contract builds
`Dict((row.turn, row.i, row.j) => ...)` at Contracts.jl:863–866 — collapses every turn onto
`-1` on this entry path. It is not reachable through `StrongStrongTask`, which is why no
contract sees it.

Repro: install a sink, call `collide!(pic_solver, b1, b2, CUDABackend, ctx)` twice with
`ctx.turn = 1` and `ctx.turn = 2` on `batch_mode=:wavefront` defaults; the records' `turn`
field must be `1` and `2` and is `-1` for both. The CPU equivalent
(`collide!(..., CPUThreadsBackend, ctx)`) records `1` and `2`.

---

### LEAD U1-5 [Low, confidence med] src/tasks/strongstrong/pic_cuda.jl:130-149, 1349-1452 — OUT OF HYPOTHESIS, cross-file seam

Claim: under `interaction_grid = :node` no particle that escapes its turn-start node mesh is
counted on **either** backend, although `_pic_prebuild_node_caches!`'s docstring justifies
turn-start mesh construction with "the zero-weight deposition guard counts any escapee
rather than smearing it".

Mechanism: node meshes are built once at turn start (region 206–212 / 83–89, CPU
pic_cpu.jl:57–62) and particles then move for a whole turn against a fixed box. The escapee
accounting the docstring invokes is `workspace.dropped[]`, incremented only inside the
`if ge !== :extrema` block of `_pic_interaction!` (pic_cpu.jl:608–636); `_pic_interaction_node!`
(pic_cpu.jl:870–938) never increments it, and `_validate_pic_solver` *forbids*
`grid_extent != :extrema` whenever `interaction_grid != :slice_pair` (pic_cpu.jl:234–241).
So the counted-escapee branch is unreachable in exactly the mode whose docstring cites it.
The CUDA twin has no `dropped` counter at all (`grep -c dropped src/tasks/strongstrong/pic_cuda.jl`
→ 0), so the region's node routes deposit and interpolate with the zero-weight guard of
`_cuda_pic_cic_weights`/`_cuda_pic_tsc_weights` (4313, 4333) silently discarding any escapee.
Both twins share the gap, so the CPU/CUDA parity contract cannot see it — the same
blind-spot shape as the retired U1-2/U5-3. Severity is Low because the mesh carries
`1.5 + _PIC_TEMPLATE_MARGIN_CELLS` cells of margin and the claim that intra-turn motion is
far smaller is plausible; the defect is that the claim is asserted and nothing measures it.

Repro (static, two commands):

    grep -n "dropped" src/tasks/strongstrong/pic_cuda.jl          # expect >0 hits, get 0
    grep -n "workspace.dropped" src/tasks/strongstrong/pic_cpu.jl # only inside `ge !== :extrema`

plus `_validate_pic_solver`'s throw at pic_cpu.jl:234–241 proving `ge === :extrema` under
`:node`. A dynamic repro would need an instrumented build (a counter does not exist to read),
which is why this is filed as a lead about a missing tripwire rather than a measured loss.

---

### LEAD U1-6 [Low, confidence high] src/tasks/strongstrong/pic_cuda.jl:670-696

Claim: after the F10 fix, `_cuda_pic_extract_slice`'s `longitudinal_kick` parameter is dead
— the body ignores it — but all eight call sites still compute and pass it, and the sibling
`_cuda_pic_store_slice!` has an identically named parameter that *is* honoured; the
now-unreachable `_cuda_pic_gather_slice_kernel!` (pic_cuda.jl:3745) remains defined with no
caller and no test.

Mechanism: the diff replaced the conditional 5-field/6-field gather with an unconditional
6-field gather and a single kernel launch (671–694), leaving `longitudinal_kick::Bool=false`
in the signature purely vestigial. Two functions ten lines apart now read the same parameter
name with opposite meaning (`_cuda_pic_store_slice!` at 698–713 branches on it). F10 was
precisely the defect of assuming the gather was conditional; the surviving parameter and the
surviving dead kernel are the artefacts that made that assumption look right. This is
cleanup, not a behaviour defect — but it is cleanup on the exact line the last audit paid for.

Repro (static):

    grep -rn "_cuda_pic_gather_slice_kernel!" src/ test/ validation/

must show a definition **and** at least one caller; it shows only the definition at
`src/tasks/strongstrong/pic_cuda.jl:3745`. Likewise `_cuda_pic_extract_slice`'s third
argument appears in the signature and nowhere in the body.

---

## Checked and found sound (with the evidence that makes it checkable)

1. **F11 (the `:node` × `pic_timing_detail` gate, region lines 220–235) is present, fires,
   and fires before any mutation.** Measured (`probe_node_detail_gate.jl`): a
   `batch_mode=:wavefront, interaction_grid=:node` solver run under
   `StrongStrongDiagnostics(pic_timing_detail=true)` raises
   `ArgumentError: interaction_grid = :node on the CUDA wavefront route requires the
   fully-indexed sub-route…`, and `beam1.x` is bit-identical to its pre-call value
   (`unchanged = true`). The message is a concatenation of string literals with no
   interpolation, and the throw is host-side (inside `_cuda_pic_collide_wavefront!`,
   not reachable from device IR).
2. **The static `:node` route gate is complete.** Measured (`probe_routes.jl` §2): each of
   `cuda_indexed_wavefront=false`, `cuda_wavefront_fft=false`, `cuda_async=false` combined
   with `batch_mode=:wavefront, interaction_grid=:node` raises `ArgumentError` from
   `_require_cuda_pic_options` (pic_cpu.jl:370–392). The previous audit's U1-1 (nine of ten
   accepted combinations silently degrading `:node` to `:slice_pair`) is closed.
3. **`:node` + `:quadratic` is rejected.** Measured (`probe_routes.jl` §3): `ArgumentError`
   from `_validate_pic_solver` (pic_cpu.jl:250–256). Previous audit U1-2 closed.
4. **Both honoured `:node` routes agree with the CPU reference.** Measured
   (`probe_routes.jl` §6–7, 4 slices, n=4000/beam):
   sequential (`cuda_async=false`) CUDA luminosity `5.378164210895914e14` vs CPU
   `5.3781642108959125e14`, max coordinate difference `1.32e-13` relative to beam scale;
   fully-indexed wavefront `5.378164210895908e14`, relative `1.28e-13`.
5. **`pic_timing_detail` does not change results outside `:node`** — and the reason it
   cannot be measured to is that the CUDA PIC deposit is atomic and therefore not bitwise
   reproducible run to run in the first place. Measured (`probe_routes.jl` §4–5): two
   identical default-wavefront runs differ by `1.25e-15` absolute (`identical = false`);
   `pic_timing_detail=true` versus `false` differs by `5.77e-16` absolute
   (`3.44e-14` relative, luminosity `2.17e-15` relative) — i.e. *below* the route's own
   run-to-run noise. The remaining route-swap that `pic_timing_detail` performs for
   `:slice_pair` solvers is therefore not a physics change, and the F11 throw's scoping to
   `:node` is correct rather than under-inclusive.
6. **The F10 fix is load-bearing and its store side is right.** `_cuda_pic_launch_kick_node!`
   (1733) and `_cuda_pic_launch_kick_quadratic!` (1923) marshal `out.pz`/`field.pz`
   unconditionally, so a five-field gather really would fail at argument marshalling on any
   `longitudinal_kick = false` gathered route. `_cuda_pic_store_slice!` (698–713) still
   scatters `pz` only under `longitudinal_kick`, and the kick kernels write `outpz` only
   under the same flag (`_cuda_pic_kick_node_kernel!` 4960,
   `_cuda_pic_kick_quadratic_kernel!` likewise), so the extra gathered plane is genuinely
   read-only and the CPU twin's unconditional six-field store (pic_cpu.jl:477–486) is
   matched in effect. `z` is never written by any kick kernel, so its absence from both
   scatter kernels is correct.
7. **Node-mesh construction is arithmetically identical to the CPU twin.** Compared
   `_cuda_pic_build_node_grids!` (1789–1841) against `_pic_build_node_grids!`
   (pic_cpu.jl:739–804) expression by expression: source drift `0.5*(c - boundary[b])` for
   all `nb` nodes; source box unioning node `b` with `min(b+1, nb)`; field box unioning
   adjacent slices `b-1, b` and skipping `±Inf` (empty) slices; NaN → `_nonfinite_coordinate_error`,
   `±Inf` → legitimate skip; the field drift `x + (0.5*(z-c))*px` associates identically on
   both sides (CUDA `co.x .+ (0.5 .* (co.z .- c)) .* co.px` vs CPU `rep.x[i] + sh*rep.px[i]`).
   `min`/`max` are exact and associative, so the different reduction shapes (per-particle
   loop vs `minimum(X, dims=2)` over a `K×n` broadcast) cannot diverge.
   `_cuda_pic_prebuild_node_caches!` (1850–1875) hoists the field gather out of the
   per-source-slice loop, which changes cost only; the turn-start build point matches the
   CPU (region 206–212 vs pic_cpu.jl:57–62).
8. **The node kick reproduces the CPU node kick term for term.**
   `_cuda_pic_apply_indexed_node_kick!` (1977–2017) and `_cuda_pic_kick_node_kernel!`
   (4927–4971) vs `_pic_interaction_node!` (pic_cpu.jl:870–938): forward drift
   `s1 = 0.5*(z - source_center)`, `zL = clamp(-z*hzi + zbias, 0, 1)`, transverse blend
   `zL*K_L + zR*K_R` with `K_L` on `gL.field_grid` and `K_R` on `gR.field_grid`,
   `kick_scale = 2*kbb`, inverse drift with the **new** momentum, and the longitudinal
   bookkeeping `pz -= 0.25(old px²+py²)` → `+= kick_scale*Kz*hzi` → `+= 0.25(new px²+py²)`
   with `Kz` read from `phiL`/`phiZ` on the **left node's** mesh. The `phiL` passed as the
   R-mesh potential argument at 1998/4952 is harmless: `_cuda_pic_interpolate_field`
   (4875–4915) never dereferences its `phiL`/`phiR` parameters.
9. **`_cuda_pic_prepare_interaction` matches the CPU bound arithmetic on the one
   `grid_extent` CUDA accepts.** CPU carries a `:sigma` estimator (`_pic_axis_extent`,
   pic_cpu.jl:974–986) that CUDA does not; `_require_cuda_pic_options` throws for any
   `grid_extent !== :extrema` (pic_cpu.jl:393–397), so the missing estimator is rejected,
   not ignored. Under `:extrema` both reduce the same drifted expressions to the same
   min/max, and both check the resulting host scalars for finiteness before any deposit
   (region 1549–1554 vs pic_cpu.jl:553–556 / 585–588).
10. **Indexed-wavefront bounds plumbing is internally consistent.** `bounds_partials` is
    allocated `(12, _CUDA_PIC_BOUNDS_PARTIAL_BLOCKS=64, 2*npairs)` (2440–2443); the init
    kernel's `row = (index-1) % 12 + 1` (4213) matches that leading dimension and the
    `(Inf, -Inf, Inf, -Inf)` neutral layout (2227–2229, 2246–2249); the force kernels write
    rows 1–8/1–12 at `block ≤ blocks1 = min(cld(n, 256), 64)` (region 1603–1604) and the
    finalize kernels read `thread ≤ blockDim = 64`, so untouched slots keep the neutral
    values the init pass wrote; both force kernels are grid-stride (`while index ≤
    length(idx)`), so capping the grid at 64 blocks cannot miss a tail; every thread reaches
    `_cuda_pic_bounds_block_reduce` (no early return before `sync_threads`), so the
    full-mask `shfl_down_sync` is legal at both 256 and 64 threads;
    `copyto!(wf.bounds_host, 1, wf.bounds, 1, length(wf.bounds))` is a contiguous
    column-prefix copy with matching 12-row strides. `nrows = compute_luminosity ? 12 : 8`
    (1646) reads only rows the finalize kernel wrote.
11. **Plane layouts and workspace capacities line up.** Node route: `6*npairs` planes
    reserved (2510–2512) and requested (1415) after the `keep` filter can only shrink
    `npairs`; the kick call sites at 1434–1446 consume `o+1/o+2/o+3` (dir 1: L on `gL1`,
    R on `gR1`, Z on `gL1`) and `o+4/o+5/o+6`, matching the documented layout at 2567–2581.
    Standard indexed route: `4*npairs`, planes `offset+1..4` passed to
    `_cuda_pic_launch_kick_pair_indexed!` in `phi12` then `phi21` order, which is the order
    that function's docstring (2066–2083) requires.
12. **No device-IR hazard in the region.** The only `throw` in lines 1–2000 is the host-side
    ArgumentError at 229 (literal concatenation, no interpolation); there is no `@assert`;
    every kernel argument marshalled from the region is isbits (`Bool` for
    `solver.longitudinal_kick` and `_pic_fourth_order(solver)`, `Int32` codes, scalar grid
    geometry) or an adapted device array. `_cuda_pic_apply_indexed_node_kick!` — the one
    device function defined in the region — contains no branch that can throw.
13. **Field solves do not alias their scratch charge buffer.**
    `_cuda_pic_solve_drifted_field_with_green_fft` returns `phi = phi_pad[1:nx, 1:ny]`, a
    fresh allocation rather than a view (pic_cuda.jl:2341–2343), so
    `_cuda_pic_interaction_node!`'s three successive solves through the single
    `workspace.charges[k]` buffer (1894–1902) cannot overwrite `phiL` while `phiZ` is built.
14. **The async and batched pair paths still consume luminosity before the in-place kicks.**
    Region 807–813 and 890–896 fetch the luminosity task and synchronize
    `luminosity_stream` *before* `_cuda_pic_launch_kick!` rewrites `old1`/`old2`; the
    comments record the 1.8e-4 regression that motivated it. The plain-sequential path
    keeps its source copy (128–129/348–349, helper at 41–49) and the batched paths deposit
    every source before any kick, which is what `collision_pair_batches`' no-repeated-slice
    property (relied on at 41–44) makes safe.
15. **`batch_mode`'s inertness on the CPU is documented, not silent.** Measured
    (`probe_sink.jl`): CPU `:sequential` and `:wavefront` give bit-identical luminosity
    `5.756043461949609e14` and identical sinks. `SolverOptionMeta` states it explicitly —
    "The CPU path only validates it and always uses collision-time order, so a non-default
    value is inactive there" (interface.jl:1436–1440) — with `supported_backends=(CUDABackend,)`.
16. **Fused Gaussian wavefront sizing (region 1057–1238) is self-consistent.**
    `nstats = centered_nstats + 4` (pic_cuda.jl:5657) covers the four anchor rows the moment
    kernel writes; `_cuda_gaussian_moment_launch(n).threads` is `_active_cuda_launch`'s
    policy `threads`, independent of `n` (Policies.jl:259–264), so the single
    `moment_threads` used for the whole batch (1118) equals the per-column value that
    `block_counts` was computed with and the shared-memory sizing at 1119 matches the
    launched `blockDim`; `blocks ≥ 1` for empty slices; the reduce, build and kick kernels
    are all grid-stride; `lum[1:lum_offset]` is fully written because exactly one of the two
    segments per pair carries `complum = 1` and `lum_offset` advances by that segment's
    length (1166–1182).
17. **Slice-pair Green cache twin parity survives the diff.** `_cuda_pic_expand_grid_by`
    (2216–2221) lacks the CPU's `factor <= 1` early return (pic_cpu.jl:1170), which is
    harmless because `slice_pair_green_growth` is validated non-negative
    (interface.jl:1249–1251) and at `factor == 1` the CUDA arithmetic is exactly the
    identity. Usability predicate, coverage margin, expand-then-realign and hit/miss/rebuild
    accounting match term for term (2185–2214, 2159–2177 vs pic_cpu.jl:1111–1180).

## Not checked, and why

- **Lines 2001–6009** are other units' regions. I read the specific functions listed under
  Provenance only to validate claims about my own region's launch configuration and twin
  parity, and I report nothing against them.
- **Production-scale behaviour of `_cuda_pic_prebuild_node_caches!`.** It gathers *every*
  field slice simultaneously (region 1859–1864), and the F10 fix raised that from five to
  six device planes per particle — a full extra copy of one beam's `pz`. At the recorded
  production point (2.56M/1.024M particles, 15 slices) that is roughly +20% on a
  multi-hundred-MB transient. I did not measure it: this GPU is shared with other agents in
  this session and a 2.56M-particle node turn would have distorted their measurements. It
  is a cost question, not a correctness one — flagged here so it is not mistaken for
  "checked".
- **A dynamic repro for LEAD U1-5.** No escapee counter exists on the CUDA path, so
  demonstrating a drop requires instrumenting the deposit — which would mean modifying a
  repository file. Filed as a missing-tripwire lead with a static repro instead.
- **`_cuda_pic_store_slice!` with an empty index** (region 698–713) would launch with
  `blocks = cld(0, threads) = 0`, which CUDA rejects. Every call site is guarded
  (region 105 and 378–379), so it is unreachable today; noted, not filed.
