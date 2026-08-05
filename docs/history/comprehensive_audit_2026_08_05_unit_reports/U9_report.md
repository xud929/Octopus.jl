# U9 report — spectral.jl / spectral_cuda.jl (Dirichlet-box double-sine Poisson solver)

Repo: /cfs/ad/dxu/Library/Julia/Octopus @ 13c2733b00533e23125544a1ef70c3cfe9b66472

## Coverage

- `src/tasks/strongstrong/spectral.jl`: **lines 1–1148, every line read** (two Read passes: 1–958, 959–1148).
- `src/tasks/strongstrong/spectral_cuda.jl`: **lines 1–806, every line read** (single pass).
- Anchors read in full: `docs/theory/spectral_sine_poisson_solver.md` (1–672). Supporting reads for
  cross-file invariants: `slicing.jl` 1–640 (slicing/mask/batches), `pic_cpu.jl` 418–898
  (`_slice_interpolation_parameters`, extract/store, PIC kick_scale=2kbb), `pic_cuda.jl`
  5170–5420 (CUDA slicing incl. `_cuda_slices_from_boundaries` degenerate branch,
  `_cuda_equal_count_slices`), `interface.jl` 460–530 + 1137–1236, `Policies.jl` 210–244,
  `Beam.jl` 180–240, `test/runtests.jl` 2812–3040 (R2/R7/R9/R10 pins + Core.Box sweep),
  `docs/history/comprehensive_audit_2026_08_04.md` (R-series remediation table, §3, §7 ledger),
  and CUDA.jl depot source (`CUDACore/NlVPI/src/device/intrinsics/atomics.jl`) for `@atomic`
  type-conversion semantics.

Probes (all CPU, run from repo root, `julia --startup-file=no --project=. <script>`):
- `U9/pA_exactness.jl` — brute-force mode-sum anchor, boundary zeros, -1x mirror, tripwire threshold.
- `U9/pB_box_mask_lum.jl` — masked box, drifted-box arithmetic, min_domain_halfwidth, degenerate slicing, luminosity closed form.
- `U9/pC_box_lowered.jl`, `U9/pC2_closure.jl`, `U9/pC3_closure.jl` — Core.Box census + chokepoint.
- `U9/pD_parity.jl` / `pD2_parity.jl` — R12 transverse vs naive reference; spectral-vs-PIC 6D collide.
- `U9/pE_pz_anchor.jl` — isolated pz potential-difference kick scale; grid_free↔grid convention.

## Leads

No new defect-grade findings. Three previously recorded ledger items re-verified as **still true at this
commit** (they are open by design/record, listed so the auditor can confirm the ledger is honest), plus one
doc nuance:

**[U9-1] src/tasks/strongstrong/spectral_cuda.jl:342-364, 422-475 — the R9 dropped-charge tripwire exists
only on the CPU deposits; every CUDA deposit (`_cuda_spectral_field!`, `_cuda_spectral_potential_solve!`,
`_cuda_spectral_potential_solve_idx!`) clips silently.** Severity: Minor (known — recorded as open in
`docs/history/comprehensive_audit_2026_08_04.md` §7/§8 "The CUDA spectral deposit has no tripwire … the
strong-kick reachability applies there too"). The reachability is real, not hypothetical: probe
`pD_parity.jl` (as first run, with kbb=1e-3) drove 69–92 % of a slice's charge out of the box
mid-collision and the CPU tripwire warned on every pair; the identical configuration on CUDA would be
silent. Repro recipe for a GPU host: run `pD_parity.jl` part 2 with `kbb1=kbb2=1.0e-3` and
`collide!(…, CUDABackend)`; assert some signal exists — none will.

**[U9-2] src/tasks/strongstrong/spectral_cuda.jl:512-534 — CUDA transverse path still solves 2·n1·n2
per collision; the R12 hoist (n1+n2 pre-solves) is CPU-only.** Severity: Perf-only, doubly non-default
(`longitudinal_kick=false` and CUDA); matches the recorded ledger note. Correctness unaffected
(positions never mutated; sources gathered per pair pre-kick).

**[U9-3] src/tasks/strongstrong/spectral_cuda.jl:340-341 — the comment above `_cuda_spectral_field!`
("writes Exg/Eyg into ws.s1/ws.s2 not used, returns (Exg, Eyg) as fresh device matrices reused via ws
buffers") contradicts the code, which `CUDA.similar`-allocates Exg/Eyg per slice pair (lines 359, 363) and
reuses nothing.** Severity: Trivial (comment drift; also a recorded ledger note). The 6D path's claim of
allocation-free solves (lines 132-135) is accurate — only the transverse helper's comment is wrong.

**[U9-4] src/tasks/strongstrong/spectral.jl:126-131 vs spectral_cuda.jl:139-141, 164-170, 589-622 —
`field_precision=:single` docstring says "keeping particle coordinates in Float64", but on the CUDA 6D
path the beam-2 source snapshot (`ws.snapx/snappx/snapy/snappy`) is allocated at the workspace precision
W=Float32, so direction 2's source coordinates and the luminosity deposit/extents are Float32-rounded.**
Severity: Trivial/doc nuance — the rounding (~1e-7 rel) is inside the error budget the docstring quotes
for `:single`, and `:double` (default/production) is unaffected; but the sentence overstates what stays
Float64. GPU-only; not probeable here. Repro recipe: on a GPU host, `:single` longitudinal collide,
inspect `typeof(ws.snapx)`.

Checked and NOT leads (explicitly cleared):
- `CUDA.@atomic rho[i,j] += <Float64>` into a Float32 `rho` under `:single`: CUDA.jl's
  `atomic_arrayset(A::AbstractArray{T}, Is::Tuple, op, val)` converts `val` to `T`
  (CUDACore/NlVPI/src/device/intrinsics/atomics.jl:435-436), so the mixed-type deposits compile and round
  correctly. Not a defect.
- Slice boundaries fed to `sL/sR = 0.5*(center − lb/rb)` are always finite: every slicing method sets the
  outer boundaries to live z-extrema and clamps internals (slicing.jl:127-128, 303-304, 325, 347-351,
  373-377), and `_finish_longitudinal_slices`/`_cuda_slices_from_boundaries` chokepoint any non-finite
  boundary. No infinite virtual drift is reachable.
- R7's remediation phrase "slice 1 … all methods" excludes `:equal_count` by design: its degenerate all-equal-z
  behavior is the rank split ([2,2,2,2] at ns=4, probe pB), which is the R1/R2 pinned rank contract, and the
  pinned tests (runtests.jl:2812-2860) assert exactly this split. Consistent, not a divergence.

## Sound — invariants verified, with how

1. **Discrete solve is exact against the continuum-anchored mode sum** (defect class 6). Delta source at a
   grid node, Nx=Ny=31, brute-force `φ_lm = −(4/ab)·sin·sin/(αl²+βm²)` with K = −4πE, Φ = −4πφ:
   `:grid` Ex/Ey to **3.3e-15**, ws-potential Φ to **1.6e-15**, `:grid_free` Φ/Ex/Ey to **≤3.7e-15**
   (pA). The prior audit's 2e-15-class claim is still earned by the current tree, on all three routes.
2. **Normalization algebra** (theory §18): `_SPECTRAL_FIELD_SCALE_GRID = −2π` and `_FREE = +4π` produce
   *identical* fields/potentials from the same source through completely different transform chains
   (grid DST/DCT with its factor-2s vs direct mode sums) — agreement at 2e-15 pins both scales and the
   potential's ½ factor (spectral.jl:512-519, cuda twin at 433-437 verified same algebra by reading).
3. **Boundary rows/columns exactly zero**: grid-path Φ/Ex/Ey at x=±Lx, y=±Ly and outside the box are
   **exactly 0.0** (interpolation guard); free-path Φ at the boundary ≤1.2e-16 of a 7.85 scale (pA).
4. **R9 tripwire** (spectral.jl:403-411): threshold behaves exactly at `deficit > 1e-9·ns` — silent
   all-inside, silent at a 5e-13 clipped fraction, warns at 5e-7 and reports `dropped_fraction`
   equal to the analytic clip (0.00990099… for 1 of 101) (pA §4). Present on both CPU grid deposits
   (solve and potential variants). Reachability via intra-collision kicks reproduced live (69–92 % drops
   at absurd kbb, every pair warned) (pD first run).
5. **R10 guard** (spectral.jl:639-648): warns on an out-of-box `:grid_free` source, and the mirror is
   measured **exactly −1.0000000000000004×** on Φ/Ex/Ey (odd extension identity θ_s+θ_m=2π) (pA §3).
   CUDA cannot reach `:grid_free` (ArgumentError at both CUDA collides, spectral_cuda.jl:492-493, 625-626).
6. **S20 / live-mask** (defect class 1): CPU `_spectral_box`/`_spectral_box_drifted` under
   `allow_lost_particles` exclude a dead particle exactly (masked box == hand-computed live-only box to
   the last bit, both plain and drifted; drifted-box arithmetic == hand formula bitwise) and the unmasked
   NaN-x case throws the directed chokepoint error (pB, pC). CUDA twins carry the same mask
   (`_cuda_live_flags` + neutral-element `ifelse.` reductions, spectral_cuda.jl:706-781) — verified by
   reading; prior audit measured 5.7e-15 CPU/CUDA parity with an S20-shaped dead particle. Every other
   extent/statistic (luminosity extents, deposits, z-stats) consumes slice indices, which slicing masks
   at the source (slicing.jl:55, 403-419) — no unmasked reduction remains in either file.
7. **R2/R7** (defect class 3): degenerate all-equal z lands in slice 1 for `:equal_area`, `:equal_width`,
   `:normal_quantile` (probe pB, CPU) with the same branch on CUDA (`_cuda_degenerate_slices`,
   pic_cuda.jl); `:specified`/`:gaussian` route through the same degenerate branch on both backends.
   `:equal_count` keeps rank membership on both backends (CPU slices the permutation, CUDA
   `_cuda_slices_from_indices`), ties-only contract pinned by tests (runtests.jl:2834-2859).
8. **R12 capture argument holds** (defect class 4): the transverse path caches `(copy(ws.Exg), copy(ws.Eyg))`
   per source slice, keyed to positions that are provably never mutated (the kick loops write only
   px/py, spectral.jl:1051-1052, 1074-1075; probe confirms x/y bit-unchanged). End-to-end: production
   collide vs a naive per-pair reference in matched accumulation order agrees to **1.1e-14 absolute on a
   26-unit kick (~4e-16 rel)** and the luminosity is **bit-identical** (pD2 §1). The stored-mesh eval is
   bit-identical (0.0) to the fused solve+eval (pA).
9. **Core.Box allowlist entry is still TRUE** (defect class 5): lowered code of
   `_spectral_collide_longitudinal!` has exactly one `Core.Box()` (stmt 3, the `luminosity` slot); both
   `setfield!(:contents)` writes are in the OUTER body (stmt 54 = init before the batch loop, stmt 199 =
   `+= sum(lum_parts)` after the worker join); contents-reads at 119/125/187/193/209/215 (pC/pC3).
   Source has no assignment to `luminosity` inside the do-block, and `_run_logical_workers` is
   `@sync`-joined (Policies.jl:233-235), so the write is ordered after all worker reads. Value-correct
   under boxing: `typeof(luminosity)` is LT throughout. The sweep-test entry (runtests.jl:2995) matches.
10. **6D map parity with PIC** (independent solver): identical beams, 64² grids, d=10, physical kick —
    px/py rel-RMS difference **1.1–1.2 %** (the documented graininess/discretization floor), luminosity
    **3.7e-10** relative, x/y ≤3.1e-4 (pD2 §2). Isolated pz potential-difference kick (cold beams):
    least-squares scale spectral = **0.974×PIC** (Dirichlet-box truncation at d=10; a factor-2 error in
    the §18 Φ=2φ_PIC / kbb·w-vs-2kbb algebra would read 0.5 or 2.0), and `:grid_free` vs fine `:grid`
    through the full longitudinal map: lsq ratio **1.0027 (pz) / 1.0010 (px)** (pE).
11. **Luminosity scale algebra**: `_spectral_luminosity_pair` vs the closed-form Gaussian overlap
    n²/(4πσxσy): ratio **0.99828** at 127², nm=2e5 (CIC smoothing accounts for the deficit) (pB §4).
    CUDA twin verified line-by-line to use the same extents/1.1-padding/deposit mapping
    ((x−xmin)/h + 1 == (x + (−xmin+h))/h) and per-pair pre-kick sources on both backends.
12. **CPU↔CUDA kernel/index arithmetic** (defect class 7): the odd/even real extensions
    `[0, A, 0, ±A-reversed]` of length 2(N+1) with rfft half-spectrum bins 2..N+1 reproduce FFTW
    RODFT00/REDFT00 exactly (derived algebraically term-by-term, including the (−1)^k mirror
    cancellations); extension/extract launch bounds cover their index ranges exactly; scratch aliasing in
    `_cuda_spectral_solve_from_rho!` is clean (s1 philm, s3 shared DST_x reused for Φ and Ey, s2
    overwritten only after consumption); one rfft plan per dimension is applied only to its own planned
    buffer. The 6D scatter kernel is algebraically identical to the CPU `_spectral_interaction!` including
    the inline `_slice_interpolation_parameters` degenerate/±Inf semantics (pic_cpu.jl:890-898: same
    (0, 0.5) fallback; inv(finite-nonzero) cannot be 0.0, so the branches coincide). Slice-pair ordering:
    CPU batches preserve per-slice collision order; the CUDA sequential sorted order is the same per-slice
    order; snapshot semantics give both directions and the luminosity pre-kick sources, matching the CPU's
    extract/copy/store discipline.
13. **Workspace lease pools**: CPU pool leases are exclusive per collision, grown/created under one lock
    with FFTW planning inside it; double-release errors; CUDA leases are device+type+shape keyed with a
    cross-stream ready-event handoff (record-on-release, wait-on-acquire) and a wrong-device release
    error. Nothing in either file shares a mutable FFT buffer across concurrent collisions.
14. **Config/error paths** (defect class 8): every stored solver field is consumed (kbb/lum overrides,
    grid, domain_factor, min_domain_halfwidth read in both boxes AND luminosity extents, method,
    longitudinal_kick, field_precision on CUDA only with `supported_backends=(CUDABackend,)` marking it
    `:inactive_backend` on CPU, schedule, slicings; requested_* feed `solver_configuration`). Constructor
    rejections (grid<8, domain_factor≤0, non-finite/negative min halfwidth, bad method/precision) all
    throw; collapsed-at-origin beams throw with the min_domain_halfwidth instruction and the bound
    substitutes exactly (L=2.5e-3 measured); the luminosity NaN-when-skipped convention is typed and
    matches PIC's.

## Probe inventory (scratch, nothing written to the repo)

pA_exactness.jl, pB_box_mask_lum.jl, pC_box_lowered.jl, pC2_closure.jl, pC3_closure.jl,
pD_parity.jl, pD2_parity.jl, pE_pz_anchor.jl under
`/tmp/claude-320114/-cfs-ad-dxu-Library-Julia-Octopus/94771dda-fd24-4438-922e-a4bd8afa2361/scratchpad/U9/`.
All runs <60 s each after package load; no repository file was modified.
