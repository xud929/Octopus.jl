# U7: spectral.jl + spectral_cuda.jl (twin pair)

Reading unit U7 of the 2026-10-18 comprehensive audit. Tree audited:
`/cfs/ad/dxu/Library/Julia/Octopus` at commit `24e8683` (read-only; no repository
file was modified and no git command was run there). Device: one RTX 4500 Ada,
`Octopus.CUDA.functional() == true`, Julia `--threads=4`. Date: 2026-10-18/19.

## Region

| File | Lines read | Depth |
| --- | --- | --- |
| `src/tasks/strongstrong/spectral.jl` | 1-1877 (all) | line by line |
| `src/tasks/strongstrong/spectral_cuda.jl` | 1-1029 (all) | line by line |

Total 2906 lines, every one read. Both files have grown since the previous audit
(U11 of 2026-08-05_b read 1153 + 913 lines): the CPU file gained the divided
(multi-process step 4g) transverse protocol, the `batch_mode` schedule, the
grid-size advisory and the workspace slots; the CUDA file gained the
`_cuda_spectral_clipped` tripwire fix, the empty-source guards, the U11-2/3/4
comments and the lane-fold box moments.

Hypotheses briefed: (1) twin divergence, in particular the R9 tripwire port and
the R12 hoist, and any branch present on one side only; (2) the sine-transform
Poisson solve against `docs/theory/spectral_sine_poisson_solver.md`
(normalization, mode indexing, boundary handling) with an independent mode-sum
check; (3) device IR of every branch and static throw messages.

## Provenance

**Read line by line:** `spectral.jl` 1-1877; `spectral_cuda.jl` 1-1029;
`docs/theory/spectral_sine_poisson_solver.md` 1-693 (all); the previous audit's
`docs/history/comprehensive_audit_2026_08_05_b_unit_reports/U11_report.md` (all).

**Read only far enough to resolve a seam the region depends on (not audited):**
`slicing.jl` 235-236 (`_flag_live` takes `Vector{Bool}`), 256-300
(`_SLICE_FOLD_LANES`, `_lane_z_moment`: lane `((i + offset - 1) % L) + 1`,
`fma` on `Val(2)`); `pic_cuda.jl` 5540-5625 (`_cuda_lane_z_moment_kernel!`,
stride-`L` lanes, serial host fold); `policies/Policies.jl` 435
(`backend_type(::MultiProcessExecutionPolicy) = CPUThreadsBackend`) and 925-985
(`_mp_current_shard` returns `(0, n)` at one rank); `interface.jl` 556-600
(`_nonfinite_coordinate_error`, including its `bad == 0` "DERIVED quantity"
branch), 2510-2560 (`_solver_divides`, `_reject_undivided_solver`), 3049-3069
(`_luminosity_schedule_evaluated`); `pic_cpu.jl` 1792-1800
(`_slice_interpolation_parameters`); `track/Track.jl` 20-32 (`TrackingContext`);
`test/runtests.jl` 22680-22700 (receipt reader idiom) and 29740-29830 (the
"CUDA spectral deposit tripwire" testset, read because LEAD U7-1 contradicts its
comment).

**Executed (all read-only, scripts and logs under
`/cfs/ad/dxu/Library/Julia/Octopus/result/comprehensive_audit_2026_10_18/probes/U7/`):**

| Probe | What it measured | Headline numbers |
| --- | --- | --- |
| `p1_modesum.jl` | independent O(N^4) mode sum from the theory note vs CPU mesh, CUDA mesh, `:grid_free`; CUDA DST/DCT vs FFTW; walls | CPU Ex/Ey/Phi 8.0e-16..2.7e-15; CUDA vs reference 8.3e-16..2.7e-15, CUDA vs CPU 1.5e-16..7.5e-16; transforms 1.4e-16..3.6e-16; `:grid_free` 7.2e-16..1.7e-15; Phi at the walls 0 / 2e-16 |
| `p1b_eigenmode.jl` | single discrete eigenmode in, mode indexing, `E = -grad(Phi)` on the mesh | leakage 1.1e-15, constant 1.8e-16..5.9e-16, `Ex=-dPhi/dx` 4.9e-16..3.1e-15 |
| `p2_tripwire.jl` | R9 port at kernel level over the `_GRID_REJECT`/NaN/Inf regime; empty source; the suite's R9 collide on both backends | CPU deficit == CUDA dropped to 0.0 (1e10..1e16, NaN, +-Inf, 8xNaN), straddle 0.49 both; ns=0 no crash, stale plane zeroed; CPU 4 warnings `nsource=128`, CUDA 1 warning `nsource=3072`, `dropped_fraction=9.7291e-02` |
| `p2b_ndep_schedule.jl` | the CUDA 6D fraction vs the luminosity schedule; device bytes per collide | same 298.876726 dropped: `nsource=2048, 1.45936e-01` (luminosity skipped) vs `3072, 9.72906e-02` (evaluated); 6D 19.2 MiB and transverse 25.2 MiB device per collide at n=40000, 15 slices |
| `p3_device_ir.jl` | every kernel compiled with `@cuda launch=false` for W = Float64 and Float32; exception sites counted in the LLVM IR | 13/13 variants compile per precision; 0 dynamic calls; `gpu_report_exception` sites: 2 per stencil kernel (the `floor(Int, X)` path of `_grid_floor`), 0 in the transform/snap kernels |
| `p4_box_receipts.jl` | `_masked_rms/_ext` and both box routes CPU vs CUDA (masked, unmasked, both dominant branches); `domain_factor` finiteness; receipt shapes; grid-size note per backend; cuFFT smooth vs non-smooth sizes | all box values bitwise; `Inf`/`1e308` accepted; CPU receipt 8 keys, CUDA 5; CPU 6 grid-transform receipts + 4 warnings at (64,64), CUDA 0 + 0; cuFFT 2.0-4.3x per transform, whole solve 1.38x (128 vs 127) and 2.7x (256 vs 255) |
| `p5_parity_single.jl` | end-to-end CPU/CUDA parity both maps; run-to-run; `:single` vs `:double`; buffer eltypes | transverse px 7.6e-16, lum bitwise; 6D py 2.3e-15, pz 1.0e-15, lum bitwise; `:single` 6D lum 1.687e-08 vs `:double`, 4.1e-09 run-to-run, transverse lum bitwise; pair-level Float32-ws vs Float64-ws 1.914e-08; `eltype(qlum1) = eltype(snapx) = Float32` |
| `p6_gridfree_fieldside.jl` | `:grid_free` field evaluated past the wall vs `:grid` | `Phi(1.05L) = -Phi(0.95L)`, `Ex(1.05L) = +Ex(0.95L) = 2.63e3`, `Ex(1.5L) = 4.0e3`, `Ex(2.9L) = -2.67e3`, no warning; `:grid` gives 0 past the wall |
| `p7_maxlog.jl` | tripwire warnings surviving a process-lifetime `ConsoleLogger` across 5 R9 collides; receipts | see LEAD U7-8 |

## Leads

### LEAD U7-1 [Moderate, confidence high] src/tasks/strongstrong/spectral_cuda.jl:882
Claim: The CUDA 6D route still adds the luminosity deposits (which structurally cannot clip) to the tripwire denominator `ndep`, so its reported `dropped_fraction` is the pre-U11-2 number (`nsource=3072`, `9.7291e-02` on the suite's own R9 configuration) and changes with the luminosity schedule for an identical dropped charge, while the flush docstring (lines 300-322), the transverse route (lines 716-719) and the suite's testset comment all state that the denominator now excludes them.
Mechanism: `_cuda_spectral_collide_longitudinal!` executes `ndep += length(idx1) + n2` inside `if compute_luminosity` after each pair's `_cuda_spectral_luminosity_idx_snap!`; the luminosity mesh is sized from both slices' drifted extrema with 0.05-cell margins, so those deposits contribute exactly 0 to `ws.dropped` and only inflate the divisor. The U11-2 fix was applied to `_cuda_spectral_collide_transverse!` only ("NOT added to `ndep`"), and the docstring of `_cuda_spectral_deposit_tripwire_flush!` ("`ndep` counts only deposits that CAN clip (2026-08-05_b audit, U11-2)") describes the fix as complete. The test "CUDA spectral deposit tripwire (R9, U9-1)" asserts only that a warning fires (`match_mode = :any`), never the `nsource` it carries, so the claim in its comment is untested. Consequence: on a turn where the luminosity schedule skips, the same event reads `0.1459`; on a turn where it runs, `0.0973` (a factor `(2m1+2m2)/(3m1+3m2) = 2/3`), and neither is the CPU's per-solve `0.8316`. Defect classes 2 (fix applied to one copy), 13 (test does not pin the changed quantity), 14 (docstring and test comment as claims).
Repro: `julia --project=/cfs/ad/dxu/Library/Julia/Octopus --threads=4 /cfs/ad/dxu/Library/Julia/Octopus/result/comprehensive_audit_2026_10_18/probes/U7/p2b_ndep_schedule.jl` prints `turn 0 (luminosity skipped): nsource=2048 dropped_fraction=1.45936e-01 dropped charge=298.876726` and `turn 5 (luminosity evaluated): nsource=3072 dropped_fraction=9.72906e-02 dropped charge=298.876726`. With the line removed the two turns report the same `2048 / 1.45936e-01`. (`p2_tripwire.jl` section (b): CPU 6D four warnings `nsource=128`, CUDA 6D one warning `nsource=3072`.)

### LEAD U7-2 [Minor, confidence high] src/tasks/strongstrong/spectral_cuda.jl:191-193, 222-223, 813-819 (and 745-746, 769-770)
Claim: Under `field_precision=:single` the 6D luminosity is still a Float32 quantity, because the two data-carrying buffers it is built from, `ws.qlum1/qlum2` and the beam-2 snapshot `ws.snapx..snappy`, are typed by the workspace, so the U11-4 fix (which retyped only the scalar arithmetic `s1/s2`, extents, `hx/hy`, and the final product) is partial; the transverse route's luminosity is bitwise independent of the option.
Mechanism: `_SpectralCudaWS{T}` declares `qlum1::CuMatrix{T}` and `snapx::CuVector{T}`, and `_cuda_spectral_ensure_snap!` grows the snapshot as `CUDA.zeros(T, n)`; under `:single` `T = Float32`. `_cuda_spectral_snap4_kernel!` therefore rounds beam 2's `x, px, y, py` to Float32 before they become direction 2's source and the luminosity's second deposit, the deposit atomics accumulate into Float32 grids, and `dot(vec(qlum1), vec(qlum2))` is a Float32 reduction whose result is then promoted. The comment at 782-791 names "the accumulators" among the quantities that had become Float32 and the code leaves them so. The transverse twin `_cuda_spectral_luminosity_pair` allocates `CUDA.zeros(T, nx, ny)` with `T = eltype(x1) = Float64`, which is why it is bitwise stable. The same workspace-typing reaches the 6D kick scale and synchro-beam geometry: `_cuda_spectral_collision_direction_6d*!` pass `T(kbb_slice)`, `T(param_source.center)`, `T(param_field.lb)`, `T(param_field.rb)` with `T` the workspace type, whereas the transverse path's `a1 = T(slices1.weight[i] * kbb2)` uses the coordinate type. The docstring (spectral.jl 137-143) describes the option as "the CUDA field-solve precision ... keeping particle coordinates in `Float64`". Classes 5/9 (option meaning vs consumer) and 14 (fix comment claims more than it delivers). Physically small (the field itself is Float32-accurate under this option), but a reported observable differs between the two routes under one option.
Repro: `julia --project=/cfs/ad/dxu/Library/Julia/Octopus --threads=4 /cfs/ad/dxu/Library/Julia/Octopus/result/comprehensive_audit_2026_10_18/probes/U7/p5_parity_single.jl` prints `eltype(ws.qlum1) = Float32 ; eltype(ws.snapx) = Float32`, pair-level `rel difference Float32-ws vs Float64-ws: 1.914e-08`, collide-level 6D `CUDA :single vs :double ... lum 1.687e-08` and `:single run-to-run ... lum 4.136e-09`, against `transverse ... lum bitwise` in both rows. Expected after a complete fix: 6D luminosity bitwise between `:single` and `:double` run on identical inputs up to the Float32 field's effect on later pairs' positions (~1e-11), not 1e-8.

### LEAD U7-3 [Minor, confidence high] src/tasks/strongstrong/spectral_cuda.jl:200-217 (vs spectral.jl:431-451)
Claim: The mesh-width advisory `_spectral_note_grid_size` and its `:spectral_grid_transform` receipt fire only from the CPU workspace constructor; the CUDA workspace builds cuFFT plans of the same logical size `2(N+1)` with no note and no receipt, and cuFFT pays the same non-smooth-size tax (2.7x per whole solve at `grid=(256,256)` vs `(255,255)`).
Mechanism: `_SpectralGridWS(Nx, Ny)` calls `_spectral_note_grid_size(Nx, Ny)`, which records the receipt with `CPUThreadsBackend` hard-coded; `_SpectralCudaWS(T, Nx, Ny)` has no such call. The solver docstring (spectral.jl 145-150) itself says the odd sizes are what make "the CUDA real-FFT optimal", so the criterion is known to apply there. A branch present on one side of the twin only (class 2/4), and a performance gate that cannot see the backend where the quantity is largest (class 15).
Repro: `julia --project=/cfs/ad/dxu/Library/Julia/Octopus --threads=4 /cfs/ad/dxu/Library/Julia/Octopus/result/comprehensive_audit_2026_10_18/probes/U7/p4_box_receipts.jl` section (4): at `grid=(64,64)` the CPU records 6 `:spectral_grid_transform` receipts and 4 "makes the DST slow" warnings, CUDA records 0 and 0; section (5): cuFFT `rfft` dim1 at N=255 19.0 us vs N=256 78.0 us (4.1x), N=127 8.0 us vs N=128 16.1 us (2.0x); whole `_cuda_spectral_field!` solve `(255,255)` 198.2 us vs `(256,256)` 530.1 us, `(127,127)` 106.3 us vs `(128,128)` 146.3 us.

### LEAD U7-4 [Minor, confidence high] src/tasks/strongstrong/spectral.jl:171
Claim: The constructor requires `domain_factor > 0` but not finite, so `domain_factor=Inf` is accepted and the collide then throws `_nonfinite_coordinate_error`'s "DERIVED quantity ... drifted position that overflowed ... or a slice moment" message naming beam 2's coordinates, while `domain_factor=1e308` is accepted and runs silently with a 1e304 half-width box.
Mechanism: `L = max(d * smax, 1.05 * emax)` is `Inf` for `d = Inf`; the `!isfinite(L)` branch (spectral.jl 1194-1206, 1260-1271; CUDA 957-963, 987-995) was written for non-finite coordinates and an empty live set and attributes the failure to the beams; `_nonfinite_coordinate_error` finds every coordinate finite and emits its derived-quantity text, which lists two causes that are not this one. `NaN` is rejected only because `NaN > 0` is false. The option schema declares `Real` with no finiteness or range (class 5: declared schema vs runtime consumer; class 6: a failure path replacing the real cause).
Repro: `p4_box_receipts.jl` section (3) prints `domain_factor=Inf: ACCEPTED`, `domain_factor=1.0e308: ACCEPTED`, and for `collide!` with `Inf` on both backends `ArgumentError: non-finite value detected during a strong-strong collision (spectral drifted Dirichlet box, beam 2), but all 500 beam macroparticle coordinates (x, px, y, py, z) are finite. The non-finite value is therefore in a DERIVED quantity ...`; with `1e308`: `NO THROW`. Expected: an `ArgumentError` naming `domain_factor` at construction.

### LEAD U7-5 [Minor, confidence high] src/tasks/strongstrong/spectral_cuda.jl:671-673 and 849-852 (vs spectral.jl:1610-1622, 1781-1791)
Claim: The `:spectral_pair_schedule` receipt has a different key set per backend (CPU adds `ranks`, `exchange`, `schedule`), contradicting the CPU comment "One receipt shape across the routes ... so a test reads the same key whichever ran".
Mechanism: The CPU routes record `(batch_mode, requested, pairs, batches, widest_batch, ranks, exchange, schedule)`; both CUDA routes record `(batch_mode, requested, pairs, batches, widest_batch)`. A reader keyed on `exchange` or `schedule` silently sees nothing on CUDA (class 2, hand-copied receipt shape).
Repro: `p4_box_receipts.jl` section (4): `transverse on CPUThreadsBackend: pair_schedule keys = (:batch_mode, :requested, :pairs, :batches, :widest_batch, :ranks, :exchange, :schedule)` vs `transverse on CUDABackend: pair_schedule keys = (:batch_mode, :requested, :pairs, :batches, :widest_batch)`; same for the 6D rows.

### LEAD U7-6 [Minor, confidence med, OUT OF HYPOTHESIS (boundary handling, CPU-only route)] src/tasks/strongstrong/spectral.jl:856-865 and 895-947
Claim: `:grid_free` guards a source outside the Dirichlet box (`_spectral_mode_sum_guard`) but evaluates the field at a FIELD point outside it through the same odd periodic extension without any guard, so such a particle silently receives the field of the image charge beyond the wall; the `:grid` route returns zero there.
Mechanism: `_spectral_free_potential_from_modes` evaluates `sin(l*pi*(x+L)/a)` and `cos(...)` through `_spectral_mode_sincos` for any `x`; for `x+L > a` the sine series continues as the odd extension, i.e. the field of a sign-flipped mirror source at `x = 2L`. Measured: `Phi(L+d) = -Phi(L-d)` exactly and `Ex(L+d) = +Ex(L-d)`, growing to 4.0e3 at 1.5L and reversing to -2.67e3 at 2.9L (interior scale 4.0e3). Reachability is the one the source guard's docstring gives: the box covers every pre-collision drifted coordinate, but the 6D field particles are evaluated after earlier pairs' kicks. The `:grid` CIC stencil skips wall and outside nodes, so `E = 0` past the wall (documented as the approximation).
Repro: `julia --project=/cfs/ad/dxu/Library/Julia/Octopus --threads=4 /cfs/ad/dxu/Library/Julia/Octopus/result/comprehensive_audit_2026_10_18/probes/U7/p6_gridfree_fieldside.jl` prints the row `1.05 L  -1.296580e-01  +2.633774e+03  +0.000000e+00  +0.000000e+00  (no warning)` against `0.95 L  +1.296580e-01  +2.633774e+03  ...`.

### LEAD U7-7 [Minor, confidence med, OUT OF HYPOTHESIS (performance, class 15)] src/tasks/strongstrong/spectral_cuda.jl:803-806 (and 1018-1024)
Claim: The CUDA 6D luminosity materializes four drifted copies of the beam-2 snapshot per slice pair for its extrema, a per-collide device allocation of exactly `4 * n1 * N2 * 8` bytes that scales with the particle count; the transverse luminosity allocates two fresh `nx x ny` grids plus their product per pair.
Mechanism: `minimum(v2x .+ v2px .* s2)` and its three siblings each allocate an `n2`-length temporary before reducing, while beam 1 on the same lines uses the allocation-free `minimum(d1x, idx1)`. `_cuda_spectral_luminosity_pair` does `CUDA.zeros(T, nx, ny)` twice and `sum(q1 .* q2)` per pair. Pooled by CUDA.jl, so cheap per call, but it is per-turn allocation proportional to `nslices x nparticles`.
Repro: `p2b_ndep_schedule.jl` second section: `n=40000 slices=15 6D: gpu_bytes=20116456 (19.2 MiB)` = `4 * 15 * 40000 * 8 = 19,200,000` within the fixed meshes; `n=20000 slices=10 6D: 6.6 MiB` (`4*10*20000*8 = 6.4e6`); `transverse n=40000 slices=15: 25.2 MiB` of which `225 * 3 * 64^2 * 8 = 22.1 MiB` is the per-pair luminosity grids.

### LEAD U7-8 [Minor, confidence med, OUT OF HYPOTHESIS] src/tasks/strongstrong/spectral.jl:570-571 and spectral_cuda.jl:327-328
Claim: The dropped-charge tripwire's only output is a `@warn` with `maxlog = 8` and it records no execution receipt, so under a process-lifetime logger it falls silent after eight events (two R9 collides on the CPU, eight collisions on CUDA) and neither the `ExecutionAudit` nor the run artifact can show that charge was dropped on later turns.
Mechanism: `maxlog` is enforced per call site per logger instance; `Test.collect_test_logs` installs a fresh logger each time, which is why the suite sees the warning on every call. Every other consumer-boundary event in these files (`:spectral_pair_schedule`, `:spectral_grid_transform`) records a receipt; the one that names a correctness event ("dropped charge is a correctness event, not a tuning statistic", line 552) does not. AGENTS.md's invariant is satisfied in letter (it warns) but the check becomes invisible after the first turns of a long run.
Repro: `julia --project=/cfs/ad/dxu/Library/Julia/Octopus --threads=4 /cfs/ad/dxu/Library/Julia/Octopus/result/comprehensive_audit_2026_10_18/probes/U7/p7_maxlog.jl` runs the suite's R9 CPU configuration five times under one `ConsoleLogger` (every collide clips charge in all four of its solves) and prints `collide 1: 4`, `collide 2: 4`, `collide 3: 0`, `collide 4: 0`, `collide 5: 0` tripwire warnings, then `ExecutionAudit consumers recorded across the 5 collides: [:spectral_pair_schedule, :spectral_grid_transform, :cpu_logical_workers]` and `any receipt mentioning dropped charge: false`. Expected after a fix: a receipt per solve or per collision carrying the dropped charge, whatever the logger does.

## Clean

Each item names what was compared and what was measured; the numbers are in the
probe logs beside the scripts.

1. **Sine-transform solve against the theory note (hypothesis 2), both backends.**
   An O(N^4) mode sum written from sections 4-7 and 18 (`rho_lm = (4/ab) sum
   rho_ij sin sin / ns`, `phi_lm = -rho_lm/(al^2+bm^2)`, `K = 4 pi grad(phi)`,
   `Phi_code = -4 pi phi`) matches the CPU mesh arrays at the interior nodes to
   Ex 8.0e-16..2.2e-15, Ey 9.3e-16..2.7e-15, Phi 6.0e-16..1.7e-15 on grids
   (9,11), (12,10), (16,24) with a non-square box (0.65, 0.40); the CUDA
   `_cuda_spectral_solve_from_rho!` matches the same reference to 8.3e-16..2.7e-15
   and the CPU mesh to 1.5e-16..7.5e-16; the CUDA deposit matches the CPU deposit
   to 3.3e-16..6.8e-16 (atomics); the CPU field-only solve equals the potential
   solve's `Exg/Eyg` bitwise (`p1_modesum.jl`).
2. **Mode indexing and `E = -grad(Phi)`.** A single discrete eigenmode `(l0, m0)`
   deposited on (10,14), (12,9), (16,16) meshes returns `philm` nonzero only at
   `(l0, m0)` (leakage 1.1e-15, peak within 3.1e-16 of `-(Nx+1)(Ny+1)/(ab)/(al^2+bm^2)`);
   the reconstructed `Phig` is the eigenmode shape to 3.9e-16..3.3e-15 with the
   predicted constant to 1.8e-16..5.9e-16, and `Exg`, `Eyg` equal `-d/dx`, `-d/dy`
   of that `Phig` to 4.9e-16..3.7e-15 (`p1b_eigenmode.jl`). `l` pairs with
   dimension 1 and `al`, `m` with dimension 2 and `bm` on both backends (the
   non-square grid and box in item 1 would have exposed a swap).
3. **CUDA DST/DCT conventions.** `_cuda_dst1!/_cuda_dst2!` equal FFTW `RODFT00`
   along dims 1/2 and `_cuda_cosderiv1!/2!` equal `_spectral_cosderiv` to
   1.4e-16..3.6e-16 on random (9,11), (16,24), (31,17) inputs; the folded
   `scale` in `_cuda_dst2!(out, ws, A, s)` equals `s .* RODFT00(A)` to 1.9e-16.
4. **Dirichlet walls.** `:grid_free` `Phi` at `x = +-L`, `y = +L` is 6e-16 / 0 /
   2e-16 against an interior scale of 3.3; the `:grid` CIC evaluation at the walls
   returns 0 exactly in x and 9e-16 in y (the wall node is skipped). Both
   backends share the skip (`1 <= i <= Nx && 1 <= j <= Ny` x4, same four weights,
   same term order), read side by side.
5. **R9 tripwire port (hypothesis 1).** CPU grid deficit `ns - sum(rho)` and
   CUDA `ws.dropped` agree to exactly 0.0 for a probe at x = 1e10, 1e12, 1e13,
   1.06e11, 1e15, 1e16, NaN, +Inf, -Inf (all 1.000000), to 3.6e-15 for a wall
   straddle (0.490000 both), and for eight NaN probes (8.000000 both); the drift
   and idx deposit kernels report 1.0 for x = 1e15. The previous audit's U11-1
   regime (silence at `_GRID_REJECT`, NaN, Inf) is closed on all three kernels
   through `_cuda_spectral_clipped`'s `lost` term (`p2_tripwire.jl` (a)).
6. **Empty source (U11-5).** `_cuda_spectral_field!`, `_cuda_spectral_potential_solve!`
   and `_cuda_spectral_potential_solve_idx!` with `ns = 0` do not launch, do not
   throw, and return the zero field; a previously filled `PhigL` (max 0.933) is
   0.0 afterwards (`p2_tripwire.jl` (c)).
7. **Device IR (hypothesis 3).** All ten spectral kernels (deposit, deposit_drift
   on arrays and on `SubArray` snapshot views, deposit_idx, interp_scatter,
   interp_scatter_6d, ext1/2, extract1/2, snap4) plus the box's lane kernel
   compile with `@cuda launch=false` for workspace precision Float64 and Float32
   with coordinate arrays Float64; zero `jl_apply_generic`/`jl_invoke`/GC-pool
   calls in the LLVM IR. The only `gpu_report_exception` sites are two per
   stencil kernel, from `floor(Int, X)` inside `_grid_floor` (static
   `InexactError`, unreachable because the branch guards `|X| < 1e15`); the pure
   transform kernels have none. No kernel builds a message at runtime
   (`p3_device_ir.jl`).
8. **Dirichlet box twins.** `_masked_rms`/`_masked_ext` and
   `_cuda_masked_rms`/`_cuda_masked_ext` are bitwise equal masked and unmasked on
   10007 random values (the lane fold with offset 0 at one rank is the kernel's
   stride-L lane; `fma` on the CPU matches the device's contracted multiply-add);
   `_spectral_box` vs `_cuda_spectral_box` and `_spectral_box_drifted` vs
   `_cuda_spectral_box_drifted` are bitwise equal for the `d*smax` branch (d=16,
   L=1.592802e-03) and the `1.05*emax` branch (d=2, L=9.450000e-04 / 9.467210e-04),
   with and without three dead NaN particles per beam under
   `allow_lost_particles`; without it all four routines refuse with the same
   non-finite-coordinate error (`p4_box_receipts.jl` (1)-(2)).
9. **End-to-end parity (R12 hoist and the restructured CPU transverse protocol).**
   3000 particles per beam, grid (32,32), 4 slices: transverse CPU vs CUDA px
   7.6e-16, py 5.2e-16, x/y/z/pz bitwise, luminosity bitwise; 6D x 6.0e-16, px
   1.2e-15, py 2.3e-15, pz 1.0e-15, luminosity bitwise; CUDA run-to-run 3.8e-16
   (transverse) and 1.7e-15 (6D) from the deposit atomics, luminosity bitwise
   both (`p5_parity_single.jl`). The CPU R12 hoist now lives in
   `_spectral_source_partials!`/`_spectral_source_meshes!` and the kick loops
   evaluate stored meshes in `i` order; the CUDA hoist in `Ex1/Ey1/Ex2/Ey2`; both
   present, same pair set.
10. **6D map transcription.** `_spectral_interaction!` and
    `_cuda_spectral_interp_scatter_6d_kernel!` perform the same operations in the
    same order (drift `0.5(z - c_src)`, `pz -= 0.25(px^2+py^2)`, `zL = clamp(-z*hzi
    + zbias, 0, 1)`, `Kz = phiL - phiR`, `pz += ks*Kz*hzi`, back-drift with the new
    momenta, `pz += 0.25(px^2+py^2)`), with `_slice_interpolation_parameters`'
    degenerate branch (`hzi = 0, zbias = 0.5`) reproduced inline; both directions
    read pre-pair sources (CPU: slice j is kicked on a scratch copy and swapped in
    after both directions; CUDA: beam 2 is snapshotted before direction 1) and the
    luminosity uses pre-kick midpoint positions on both -- confirmed by the
    bitwise luminosity in item 9.
11. **Luminosity mesh cannot clip.** With `tx = width/(nx-1.1)`, `width += 0.1tx`,
    `xmin -= 0.05tx`, `hx = width/(nx-1)`, the data span maps to
    `X in [1.05, nx - 0.05]`, so every stencil node is inside for `nx >= 8` (both
    backends, both routes); consistent with the measured 0.0 contribution of
    those deposits to `ws.dropped`.
12. **Schedules and receipts (CPU).** `batch_mode` is read at the consumer
    (`batched = requested === :wavefront && npairs > 1`), the receipt reports what
    ran (`:wavefront` with `batches=5, widest_batch=3` at 3x3 slices; `:order_free`
    on the transverse route; `:sequential` on CUDA), `compute_luminosity` goes
    through the shared `_luminosity_schedule_evaluated` consult, and `NaN` is
    returned when the schedule skips (`p2b`: `returned NaN` at turn 0).
13. **Workspace leasing.** Both pools are lock-guarded, grow under the lock, refuse
    a double release, release in `finally`; the CUDA lease records a `CuEvent`
    before publishing and the next borrower waits on it; the CPU slots (`src_x`,
    `phi_buf`, `mid_x`, two each) are consistent with the L/R and direction
    aliasing described in their comments. Read; not raced.

### Notes too small to be leads

- `_masked_ext` sentinels differ: an unmasked `Inf` gives CPU `NaN` / CUDA `Inf`,
  an empty live set gives CPU `-Inf` / CUDA `NaN`. Every caller only tests
  `isfinite`/`isnan` before throwing, and all four box routines refuse (item 8),
  so no behavioural divergence was found.
- `spectral_cuda.jl:698` rebinds `W = eltype(ws.rho)` (same value as line 659).
  In the 6D kernel `zbias = hzi == 0 ? eltype(x)(0.5) : field_rb * hzi` infers
  `Union{Float32,Float64}` under `:single`; compiles and runs.
- Under `:single` the transverse route deposits with workspace-typed `T(Lx)`
  (Float32) and interpolates with coordinate-typed `T(Lx)` (Float64), a
  ~1e-5-cell mesh shift between the two; far below the Float32 field error.
- The CUDA routes carry no `_mp_*` logic; `MultiProcessExecutionPolicy` is
  CPU-only by `backend_type`, so this is unreachable through a policy. A bare
  `collide!(..., CUDABackend)` at more than one MPI rank would reach
  `_spectral_luminosity_scale`'s `_mp_current_shard` without `_with_beam_shards`;
  cross-file seam, not pursued.
- Theory note section 9's sentence about the inverse transform carrying
  `1/[2(Nx+1) 2(Ny+1)]` describes the generic DST pipeline; the code normalizes
  the forward transform by `a*b*ns` to continuum coefficients and absorbs the
  reconstruction's factor 4 in `0.5 * (-2 pi)` (section 18). Verified equivalent
  (item 1); a reading aid only.
- `_spectral_mode_sincos` never re-anchors its Chebyshev recurrence; the note's
  own figure (2e-13 at l = 2000) covers every grid the constructor accepts.

## Unchecked

- **Concurrency.** The CPU lease pool and the CUDA event hand-off were read, not
  raced (two simultaneous collides on one device or in one process). Thread-count
  invariance of the restructured CPU transverse protocol (`sum(lum_parts)` by
  slice, directions chunked by field slice) was read as data-determined and is
  pinned by the suite; I did not re-measure it at 1 vs 4 workers.
- **The divided (multi-process) protocol in `spectral.jl`** (`_spectral_box_verdict`,
  `_spectral_source_partials!/_meshes!` folds, `_spectral_transverse_luminosity!`
  grouping, the `_spectral_sliced_transport!` hand-off into `spectral_sliced.jl`)
  was read for one-rank equivalence only; no MPI run was made and
  `spectral_sliced.jl` is outside this unit.
- **`:grid_free` accuracy** beyond the mode-sum identity (truncation, convergence
  with mode count) and the physics-accuracy tables of the theory note's sections
  16 and 18 were not reproduced; they are validation-campaign claims, not
  twin-divergence questions.
- **Performance claims** in the docstrings (the 1.5x PIC ratio, the 70% solve
  share) were not benchmarked; only the relative cuFFT size tax in LEAD U7-3 and
  the allocation counts in LEAD U7-7 were measured.
- **`field_precision=:single` beyond LEAD U7-2.** I established that the 6D
  luminosity, snapshot, kick scale and drift geometry are Float32 under it; I did
  not survey whether any receipt records the precision that ran.
- Cross-file seams flagged and stopped at: `_lane_z_moment`/`_cuda_lane_z_moment_kernel!`
  (slicing.jl, pic_cuda.jl), `_nonfinite_coordinate_error` (interface.jl),
  `_pic_slice_states`/`_pic_copy_slice!`/`_pic_store_slice_states!` (pic_cpu.jl),
  `_slice_collision_order`/`collision_pair_batches` (slicing.jl),
  `_cuda_longitudinal_slices`/`_cuda_live_flags` (pic_cuda.jl). Each was read only
  far enough to confirm the contract the twin pair relies on.
