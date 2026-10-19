# U35: test/runtests.jl lines 22526-25667 (multi-process seam tests, CUDA pins, contract guards, one_turn_matrix, misc regressions)

## Region
`/cfs/ad/dxu/Library/Julia/Octopus/test/runtests.jl` lines 22526-25667 (3142 lines), tree at commit 24e8683.
36 `@testset`s plus the top-level helpers they share (`_OTMUnimplementedMethod`, `_otm_*`, `test_beam`,
`nonfinite_test_rep`, `expect_nonfinite_error`). Four sections sit behind `_lane_gate` (MPI seam 23018-23811,
MPI harnesses 23813-23960, contract coverage guards 24154-24361, lattice cells 24733-24826).

## Provenance
READ line by line, in eight consecutive chunks: 22526-22870, 22870-23200, 23200-23520, 23520-23830,
23830-24160, 24160-24500, 24500-24890, 24890-25250, 25250-25667 (every line of the region).

READ outside the region, only where a lead or a clean claim needed the consumer or the twin:
- `test/mpi_seam_check_fixture.jl`: `_mpi_check_pic_layout` (457-460, calls production `Octopus._pic_sliced_layout`),
  `_mpi_check_pic_groups` (464), `_mpi_check_pic_partials` (470-480), `_mpi_check_arm_slicing` (420), the gpic variants.
- `test/mpi_seam_check.jl`: the print sites of `MPI-LUM`, `MPI-MOM(ROWS)`, `MPI-LOSS`, `MPI-SNAPIDS`, `MPI-LOSSIDS`,
  `MPI-LOSSSUM`, `MPI-COLLIDE(SEQ)` (lines 171-302, by grep) to confirm the parent's parsing assumptions.
- `test/runtests.jl` header: `_lane_gate` (23), `using MPICH_jll` (50), `CUDA_TESTS_ACTIVE` (132), the suite-wide
  CUDA skip banner (159).
- `src/tasks/strongstrong/slicing.jl`: `_slice_moment_local_sums!` 894-974 (the serial/chunked branch),
  `_slice_transverse_moments` 1032-1060, the slice centre fold 655-700; `interface.jl:624`
  (`_STRONG_STRONG_PARALLEL_MOMENT_MIN = 4096`).
- `src/tasks/strongstrong/spectral.jl`: `_spectral_note_grid_size`, `_spectral_max_prime`, `_spectral_smooth_grid` (431-).
- `src/tasks/strongstrong/pic_cpu_sliced.jl:2190`, `spectral_sliced.jl:742-746` (the production loop-choice rule).
- `src/tasks/BeamObservers.jl`: `_moment_observer_row` (1062-), `_compute_moment`; `src/policies/Policies.jl:802`
  (`_masked_global_sum`); `src/tasks/BPMObserver.jl` 270-305; `src/beam/Beam.jl` 753-770 (`_mean`), 812- (`beam_statistics`).
- `src/elements/aperture.jl` 356-392 (`_aperture_bump!`); `src/contracts/Contracts.jl` 444-470 and 735-775
  (when `PublicConfigurationEffectivenessContract` returns `:skipped`).
- `docs/theory/bpm_measurement_model.md` 92-110 and 228-233; `docs/design/testing_lanes.md` (grep "skip").

EXECUTED (scratch: `/cfs/ad/dxu/Library/Julia/Octopus/result/comprehensive_audit_2026_10_18/probes/U35/`, logs beside each script):
1. `probe_chunked_vs_serial.jl`: `_slice_transverse_moments` over 12000 members (chunked branch, threshold 4096,
   4 threads) against an independent serial shifted-sum fold over the SAME members: rel diff sx 1.9e-16, sy 7.7e-16;
   mx/my differ by ~2.4e-20 absolute (the means are ~1e-8, so 1.9e-12 relative to a cancelled quantity).
   The suite's own comparison `same.mx == serial.mx` evaluates `true` because both calls are identical (members `few`).
2. `probe_armloop_groups.jl`: beam-1-only vs max-over-both-beams loop choice for all 21 PIC/gpic arms at P = 1, 2, 4:
   `mismatches between armloop's rule and production's: 0`; every arm has `groups1 == groups2`
   (`[1,1,1]` at P = 1, 2; `[1,1,2]` at P = 4; `skewed` `[1,2,1]` at P = 4; `sparse` all ones).
3. `probe_marker_bitwise.jl`: misaligned `MarkerSpec(x_offset=1e-3, y_offset=-8e-4)` vs plain marker: bitwise equal on
   the suite's one coordinate set; NOT bitwise on 6884 of 20000 random sets in +-5e-3 (worst |diff| 4.3e-19 = 1 ulp);
   with power-of-two offsets not bitwise on 5810 of 20000.
Not executed: the two MPI launcher testsets (30-minute class), the CUDA testsets, the example/harness children.

## Leads

### LEAD U35-1 [Moderate, confidence high] test/runtests.jl:22912-22915
Claim: The comment "Both branches over the SAME members agree to the fold difference" is backed by a comparison of the serial branch with itself (`same` repeats the `serial` call on `few`), so the chunked branch of `_slice_transverse_moments` is compared with nothing in this testset; only `isfinite(chunked.mx) && chunked.sx > 0` is asserted.
Mechanism: the serial/chunked choice is made inside `_slice_moment_local_sums!` from `length(idx) < _STRONG_STRONG_PARALLEL_MOMENT_MIN` (4096), so the public signature cannot run both branches on one member list; the test re-ran the serial call instead, which is a determinism check of one branch, not the cross-branch agreement the comment claims. A `_chunk_bounds` or `local_sums` merge defect in the chunked branch (the very property the divided form "has to preserve", per the comment at 22894-22900) would pass this testset. Class 13 (test quality: a check that does not execute what it claims).
Repro: `julia --project=/cfs/ad/dxu/Library/Julia/Octopus --threads=4 /cfs/ad/dxu/Library/Julia/Octopus/result/comprehensive_audit_2026_10_18/probes/U35/probe_chunked_vs_serial.jl` prints `suite's check same.mx == serial.mx (same inputs, same branch): true` and `shared members compared by the suite: none across branches`; the independent serial fold agrees with the chunked branch to 1.9e-16 (sx) and 7.7e-16 (sy), so the production code measures sound and the defect is the unexecuted claim. Durable pointer: `grep -n "same = Octopus._slice_transverse_moments(wide, few" test/runtests.jl` (the `same` call takes `few`, the `serial` call's list). Fix shape: fold the 12000 members serially in the test (as the probe does) and compare at the fold-difference tolerance, or state that the cross-branch agreement is pinned elsewhere (the MPI `:big` arms) and drop the claim.

### LEAD U35-2 [Minor, confidence high] test/runtests.jl:22583-22584
Claim: The Gaussian-PIC anti-fallback guards `all(s -> s.exchange === :sliced, mp[4])` and `all(s -> s.exchange === :none, cpu[4])` are vacuously true on an empty receipt list; the spectral sibling at 22707-22708 asserts `!isempty(mp[4]) && all(...)`, this one does not.
Mechanism: `all` over `[]` is `true`. The `:pic_pair_schedule` receipt is recorded today on the gpic path (`gaussian_pic.jl:1053`, `:1082`), so the guard is effective now; but a renamed consumer or a route that stopped recording would make the arm pass its schedule check without having seen a receipt, which is exactly the "comparing the path with itself" failure the comment at 22580-22582 names. Class 1/13 (a check whose anti-vacuity is itself unguarded).
Repro: `julia -e 'println(all(s -> s.exchange === :sliced, Any[]))'` prints `true`; `grep -n "all(s -> s.exchange === :sliced, mp\[4\])" test/runtests.jl` shows the unguarded form and `grep -n "!isempty(mp\[4\]) && all(s -> s.exchange === exchange, mp\[4\])" test/runtests.jl` shows the guarded sibling.

### LEAD U35-3 [Minor, confidence high] test/runtests.jl:24586-24590 (cross-file seam: docs/theory/bpm_measurement_model.md:98-106)
Claim: The pin that a misaligned `MarkerSpec` tracks bit-identically to a plain marker holds at the one coordinate set tested and fails by 1 ulp on about a third of random coordinate sets, so it rests on the rounding of those particular numbers; the theory note generalises the same single measurement ("the two cancel ... the map is bit-identical", with the `0.0` difference table).
Mechanism: `_misalign_frames` subtracts the offset at the entrance and adds it back at the exit; `(x - dx) + dx == x` is not an IEEE identity, it depends on the operands' exponents. For `u = (3e-3, 3e-4, -2e-3, -2.2e-4, ...)` with `dx = 1e-3`, `dy = -8e-4` both coordinates happen to round back exactly, so the assertion `collect(moved(u...)) == collect(plain(u...))` passes by coincidence of the fixture. Class 8 (a pin resting on rounding, and a measured statement quoted as a general property) with a class-14 seam in the theory note. The physics content (a zero-length element cannot carry a reading offset) is correct.
Repro: `julia --project=/cfs/ad/dxu/Library/Julia/Octopus --threads=4 /cfs/ad/dxu/Library/Julia/Octopus/result/comprehensive_audit_2026_10_18/probes/U35/probe_marker_bitwise.jl` prints `suite's u: bitwise equal = true`, `random coordinates in +-5e-3: not bitwise on 6884 of 20000 (worst |diff| = 4.336808689942018e-19)`, `power-of-two offsets: not bitwise on 5810 of 20000`. Durable pointer: `grep -n "collect(moved(u...)) == collect(plain(u...))" test/runtests.jl`. Fix shape: assert `isapprox(...; rtol=4eps())` and say "identity to rounding" in the note, or pick a fixture whose identity is provably exact and say why.

### LEAD U35-4 [Minor, confidence med] test/runtests.jl:24280, 24799-24800, 24823-24824
Claim: Three CUDA-dependent checks are written `@test status === :passed || (status === :skipped && !CUDA_TESTS_ACTIVE)`, so on a GPU-less host (CI) an unrun check is recorded as a Pass in the summary rather than as a skip, while the region's ten other CUDA gates use `@test_skip` (48 suite-wide) and the suite's invariant is "an unrun check is not a pass".
Mechanism: the `||` form was the 2026-08-05_b U18-3 fix for the "GPU present but contract skipped" case and is right there; its other disjunct converts a legitimate skip into a pass. For `PublicConfigurationEffectivenessContract` the `:skipped` status specifically means "CPU configuration checks passed; CUDA effectiveness was skipped" (`Contracts.jl` ~760), so the CPU half did run, but neither the per-testset summary nor the `@info` (which fires only when status is not `:passed`, so it does fire here) distinguishes it from a pass. Mitigation: the one suite-wide banner at `runtests.jl:159` (`@test_skip "CUDA device not available -- GPU half of the suite skipped"`), one line for the whole suite; `testing_lanes.md` says nothing about this per-assertion form. Class 1 (subtler form).
Repro: `grep -c "=== :skipped && !CUDA_TESTS_ACTIVE" test/runtests.jl` prints `4` (three in this region, lines above); on a host where `Octopus.CUDA.functional()` is `false` the three assertions pass and no Broken/Skipped entry appears for them in the testset summary. Fix shape: `CUDA_TESTS_ACTIVE ? (@test status === :passed) : (@test_skip "CUDA leg not run")` keeps the U18-3 property and makes the skip visible.

### LEAD U35-5 [Minor, confidence med] test/runtests.jl:23605-23608
Claim: `armloop(P)`, the testset's third restatement of the "which loop did `:auto` pick" rule, reads only beam 1's layout, while the production rule (`pic_cpu_sliced.jl:2190`, `spectral_sliced.jl:742-746`) and the testset's own two other derivations (23482-23484, 23711-23713) take the maximum over both beams' widest group.
Mechanism: `_mpi_check_arm_slicing(armsolver)` returns `slicing1` and the groups are taken on `_mpi_check_ss_beams(...)[1].rep` alone; the expectation agrees with production only while beam 2 (192 particles) never has a wider group than beam 1 (256). Today it does not (measured), so this is hand-copied knowledge drifting toward a wrong expectation (a red test on a correct tree, not a false pass) rather than a false pass. Class 2.
Repro: `julia --project=/cfs/ad/dxu/Library/Julia/Octopus --threads=4 /cfs/ad/dxu/Library/Julia/Octopus/result/comprehensive_audit_2026_10_18/probes/U35/probe_armloop_groups.jl` prints `mismatches between armloop's rule and production's: 0` and `groups1 == groups2` for every arm at P in {1, 2, 4}. Durable pointer: `grep -n "_mpi_check_ss_beams(CPUThreadsExecutionPolicy(threads=1))\[1\].rep" test/runtests.jl` finds the one-beam derivation. Fix shape: one local `want_loop(solver, P)` used by all three sites, taking both beams like production.

Out-of-hypothesis, style only (no lead): `run(policy, solver)` at 22557 shadows `Base.run` inside its testset; `line(which, solver)` at 22547 ignores `which`; `one`/`two` are rebound six times across the MPI seam testset (all uses are sequential, no misuse found).

## Clean
Checked and found sound, with what was compared:
1. 22600-22644 spectral mesh-width note: thresholds read in `_spectral_note_grid_size` (`N >= 48`, largest prime `> 7`); the three cases agree (16: below the size floor; 48: logical 98 = 2*7^2 smooth; 128: 258 = 2*3*43, suggestion 127 whose logical 256 is 2-smooth; 64: 130 = 2*5*13 -> 13). Asserts on receipts, not log lines.
2. 22781-22836 `masked == reference` bitwise: `_moment_observer_row` -> `_masked_global_sum` and `_compute_moment` are serial slot-ordered folds skipping dead slots (Policies.jl:802, BeamObservers.jl), so the masked 4000-slot row and the 3996-survivor row sum the same values in the same order; structural, as the comment argues.
3. 22646-22779 solver roster tripwire derived from `Octopus._solver_contract_types()` with the fallback's ANSWER checked through `invoke`; the two-loop comparison records which loop ran (`outs[1][4] === :batched && outs[2][4] === :dataflow`) inside the policy scope; every arm must differ from `:default` except `:sequential`, which must match.
4. MPI seam parent parsing (23128-23263): `MPI-LOSSIDS` leads with the count (child line 239) so `> 10` is a count; `MPI-SNAPIDS` is the id list (child 237) -> 24 ids over two turns; `delivered` is asserted against `n` (23108-23110), the anti-vacuity for silent ranks; `@test_broken false` when the launcher is missing is visible. `out4` lacks the `resolved_by=mpi_communicator` / `MPI-CHECK FAIL` assertions given to `out1`/`out2`, but `got4 == 4` cannot be met by a passthrough fallback (every process would write `rank_0.txt`) and `ok4` covers a FAIL exit.
5. Layout-rule expectations (23478-23486, 23501-23506, 23707-23715) derive from the production `_pic_sliced_layout` through the fixture, which is circular for the rule itself, but the layout OUTCOMES are pinned independently at 23509 (a slice on >= 2 ranks at P = 4), 23766 (`sparse`: >= 40 whole slices, max 1) and 23770 (`skewed == [1, 2, 1]`); probe 2 reproduced `[1,1,2]` (default, P = 4) and `[1,2,1]` (skewed).
6. CUDA gates in the region: 23973/24007, 24021/24099, 24281/24358, 24552/24571, 25534/25561, 25581/25621 all skip visibly with `@test_skip`; 23806 asserts `cuda_status === :not_run` (not passed) when inactive; 24075's `all(... caps)` is backed by `!isempty(caps_any)` and `any(>(384), requested_any)`.
7. 24540-24544 `_aperture_bump!` with ids 0 and 2 on a one-row record: documented inert (aperture.jl:369-376, the loss surfaces through the unattributed-loss warning); the pin matches the documented semantics.
8. 24600-24601 BPM zero-error reading `==` `beam_statistics` mean: at one rank with no lost particles both call the same `_mean(v) = sum(v) / length(v)` (BPMObserver.jl:273, Beam.jl:753/766); structural.
9. 25548 `Array(sg.center) == Array(sc.center)` under tied z: the CPU centroid uses `_lane_indexed_sum_local`, the canonical lane fold shared with the CUDA centroid kernel (slicing.jl, "U6-7" comment); `weight` is `members / total` and `boundary` is a particle's z; bitwise by design.
10. Negative controls present and read: SymplecticityContract liar kind with registry restore (24192-24204), broken baseline (24208-24214), probe-less solver (24218-24223), Philox bumpless variant differs (24457-24466), ForwardDiff guard leaves incl. a plain error that must NOT be relabelled (25104-25117, 25182-25194, 25248-25250), finite difference lower bound "catches a finite difference that secretly became exact" (24988), fixed-point residual `> 0` off the origin (25341).
11. `one_turn_matrix` bitwise pins (24895-24896, 24919, 24924, 24930-24932, 25317, 25332, 25343, 25345): the helper replaced the inline closure with the same fold order, step and division, kept here as the independent witness; tolerances stated as `c * eps * kappa` with the measurement cited; `3.0e-7^2` parses as `3.0e-7^2` (power binds tighter) as intended at 25092.
12. 25405-25452 chunked (2+4) vs continuous (6) turns bitwise: counter RNG keyed by turn and rng_id; structural.
13. 23018, 23813, 24154, 24733 lane gates: `_lane_gate` (line 23) prints a `LANE SKIP` per section and the final banner (testing_lanes.md:24-26); `MPICH_jll` is imported at line 50; both MPI children are bounded by a 1800 s watchdog and read receipts from per-rank files, not the merged stdout.
14. Top-level helpers at 25398-25403 and 25474-25496 are consumed later in the suite (lines 25673 onward, 27569 onward, ...), not dead.

## Unchecked
- The MPI launcher testsets (23019-23811, 23814-23959) were read, not executed: a run is in the 30-minute class per child, and the brief asks for measurements, not waits. The parent-side logic was checked against the child's print formats only for the tags questioned above; the rest of `test/mpi_seam_check.jl` and `test/mpi_seam_check_fixture.jl` is outside the region and was not read whole.
- The CUDA testsets (23962, 24011, 24281-24356, 24547, 25498, 25565) were read, not run on the device; the one-thread subprocess test (22938-22981) was not run.
- The measured constants in the `one_turn_matrix` tests (C = 343, ratio 100, 1.0e-9 Frobenius floor, C = 3.7e12 on the strong-beam line) were not re-measured; the brackets are read as consistent with the cited measurements.
- The PTC reference table (24667-24731) was not opened; the test's non-tolerant `status === :passed` and the `_ptc_reference_path(...) !== nothing` guard were read.
