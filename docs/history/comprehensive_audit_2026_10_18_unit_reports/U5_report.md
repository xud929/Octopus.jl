# U5: pic_cpu_sliced.jl (new since the last audit)

Comprehensive audit 2026-10-18, reading unit U5. Tree: `/cfs/ad/dxu/Library/Julia/Octopus` at
commit 24e8683, read-only. Every claim below is a LEAD, not a finding.

## Region

- `src/tasks/strongstrong/pic_cpu_sliced.jl`, lines 1-2228 (2228 lines; the whole file).

Hypotheses briefed: (1) consistency with `pic_cpu.jl` and `slicing.jl` -- the same particle lands
in the same slice with the same weight on both routes; (2) dropped charge at slice boundaries and
empty slices, loud or silent; (3) per-turn allocation scaling with the particle or slice count.

## Provenance

READ line by line (the region): 1-300, 300-600, 600-900, 900-1200, 1200-1500, 1500-1850,
1850-2228. Nothing in the region was skipped.

READ for comparison (reference code, not audited line by line): `pic_cpu.jl` 1-60, 88-140,
140-560, 574-586, 717-728, 1070-1100, 1100-1530 (`_pic_interaction!`, the kick kernels),
1800-1990 (`_pic_axis_extent`, the outside-box counters, `_pic_interaction_grids`), 2222-2460
(the plane solve and the deposits), 2820-2890 (`_pic_field!`), 2960-3061 (luminosity);
`slicing.jl` 631-800 plus a structure grep; `policies/Policies.jl` 195-215, 262-300, 416-432,
520-540, 1040-1170 (the serial seam); `interface.jl` 640-667, 685-760; `gaussian.jl` 300-340
(`_divided_slice_plan`); `test/runtests.jl` 22380-22600 (the one-rank pins); the single-beam
migration's callers grepped across `src/ test/ validation/ examples/ profiling/`;
`docs/design/multi_process_policy.md` 396-500 and 551-660; `docs/history/multi_process_step4d_sliced_2026_09_05.md`
(grep, line 32); `docs/experiences.md` 360-372 and 840-880;
`docs/theory/slice_longitudinal_interpolation.md` 28-40 and 138-150 (drift and `param` conventions).
`docs/theory/gaussian_longitudinal_slicing.md` was only grepped (see Unchecked).

EXECUTED (scripts and logs under `result/comprehensive_audit_2026_10_18/probes/U5/`; every run
`julia --project=/cfs/ad/dxu/Library/Julia/Octopus --threads=4 <script>`, one rank, serial
passthrough, Float64 beams, `set_global_rng!(seed=4242, method=:philox)`):

| probe | what | result |
|---|---|---|
| `alloc_migration.jl` | `@allocated` of `_pic_sliced_migrate_pair_in` (steady state, 3rd call), ns=5 | 1,171,152 B at 20k/beam; 4,803,920 B at 80k/beam (29.3 and 30.0 B per migrated particle). Reference `push!` of N Ints: 421,824 B (20k), 1,758,192 B (80k). Slice-count scaling at 40k/beam: 2,378,944 (ns=5), 2,396,528 (15), 2,459,168 (45) |
| `alloc_collide.jl` | `@allocated` of one steady-state `_pic_collide!` under a one-rank `MultiProcessContext`, grid 32 | see table under LEAD U5-2 |
| `layout_props.jl` | 3000 random `(counts, P)` cases, P in 1:70, ~15% empty slices | 0 violations of: groups contiguous, ascending, inside 0:P-1, disjoint when P > ns, every part non-empty, parts partition `1:counts[s]`, `_pic_sliced_rank` consistent with `_pic_sliced_mine`, all P ranks used when P > ns and N >= P |
| `verdict_split.jl` | records -> reduce -> `_pic_sliced_grids` per direction, Float32, `grid_extent=:sigma` | `red[61] = 0.0`; direction 1: finite grids; direction 2: `nothing`; `SPLIT VERDICT = true` |
| `bitwise_threaded.jl` | sliced route (both loops) vs undivided CPU collide, 20k/beam, ns=15, grid 32, 3 turns, variants default/sigma/quadratic/tsc/sequential/green_none | every variant and loop bitwise equal (coordinates and luminosity); the `dropped_cpu=0 vs 3` column in this log is a probe artefact (it read `ws[1]` only), corrected by the next row |
| `bitwise_sigma_small_dropped.jl` | same, `:sigma` only, dropped summed over the workspace pool | `dropped_cpu=3 dropped_mp=3`, bitwise |
| `bitwise_threaded_big.jl` | 120k/beam, ns=5, grid 32 (24k per slice: kick maps threaded, deposit predicate false) | default/sigma/quadratic/tsc, both loops, bitwise, dropped 0 == 0 |
| `bitwise_threaded_deposit.jl` | 120k/beam, ns=5, grid 16 (predicate still false: 24000 < 160*256) | default/sigma/tsc, both loops, bitwise |
| `bitwise_threaded_deposit_big.jl` | 400k/beam, ns=5, grid 16, `_pic_deposit_parallel(80000,16,16) = true`, 2 turns | default and TSC, both loops, bitwise, dropped 0 == 0 |
| `alloc_green_none.jl` | steady-state `@allocated` per collide, 20k/beam, ns=15 (225 pairs), `green_cache` `:slice_pair` vs `:none`, sliced vs undivided | see LEAD U5-6 |

## Leads

### LEAD U5-1 [Moderate, confidence low] src/tasks/strongstrong/pic_cpu_sliced.jl:1259
Claim: The non-finite verdict of a pair is decided per DIRECTION on its two owners but jointly on its members, so a pair whose extents are finite in one direction and non-finite in the other leaves a non-member owner waiting for partials no member will send -- a hang, not the agreed throw the design promises.
Mechanism: `_sliced_owner_grids!` (1024-1041) returns `nothing` and sets `g[1] = 1` from ITS direction's `_pic_sliced_extents` alone (716-741); the shared `red[61]` flag covers only non-finite record BOUNDS, not a non-finite estimator result. A member then sets `pr.bad = grids_in[1][1] > 0 || grids_in[2][1] > 0` (batched 1259, dataflow 1906) and skips the whole pair, deposits included. A rank that is only the owner of the finite direction takes the `elseif` (1261-1262 / 1907-1908) with `owned[d] !== nothing` for its direction, so `pr.bad` stays false: in the batched loop it posts `_mp_irecv!` for every source member's partial (1286-1299) and `_mp_wait_all(reqs, :wait_deposits)` (1303) never returns; in the dataflow loop the partials were posted a stage early (1887-1897) and `recv[_PIC_DF_SOLVE]` never completes, so `_mp_wait_any` blocks forever; a member that ALSO owns the finite direction retires its planes to the pool (`_pic_df_retire!`) with those receives still posted, and the next collide's same-tag messages can land in a reassigned buffer. `nbad_all` (2222) is never reached, so the "every rank throws or none" rule (2219-2225) cannot fire. Reachability today: the per-direction `nothing` needs `_pic_axis_extent` to return a non-finite extent from finite bounds, which in the current code happens only when the `:sigma` shifted second moment overflows (Float32 |px| ~ 1e22 at a nonzero source drift and a zero field drift; Float64 ~1e154), and a non-member owner needs P >= 3. The structural gap -- nothing reconciles the two owners' verdicts with each other or with the members -- is certain; the trigger is near-unreachable with physical coordinates, hence the low confidence on severity.
Repro: `julia --project=/cfs/ad/dxu/Library/Julia/Octopus --threads=4 /cfs/ad/dxu/Library/Julia/Octopus/result/comprehensive_audit_2026_10_18/probes/U5/verdict_split.jl` prints `red[61] (joint non-finite verdict) = 0.0`, `direction 1 grids: finite grids`, `direction 2 grids: nothing`, `SPLIT VERDICT = true` (the precondition, at the unit level; the hang itself needs P >= 3 under a launcher and was not run). Durable check: `grep -n "pr.bad = pr.grids_in\[1\]\[1\] > 0 || pr.grids_in\[2\]\[1\] > 0" src/tasks/strongstrong/pic_cpu_sliced.jl` (two sites) against `grep -n "owned\[d\] === nothing && continue\|if pr.owned\[d\] !== nothing"` (the owner's per-direction gate).

### LEAD U5-2 [Minor, confidence high] src/tasks/strongstrong/pic_cpu_sliced.jl:390
Claim: The pair migration allocates about 30 bytes per migrated particle per collide, against the design intent stated at 140-146 that its buffers are pooled; 72% of it is two `push!`-grown `bucket = Int[]` vectors, the rest the scratch buffers of two `MergeSort` `sortperm!` calls.
Mechanism: `_pic_sliced_migrate_pair_in` keeps the merged permutation in the pooled `sc.bucket` (376) but builds each beam's `bucket` fresh (`bucket = Int[]` at 390, `push!(bucket, col)` at 405) for every one of this rank's received columns, every collide; `sortperm!(...; alg=MergeSort)` at 359 and 376 allocates an n/2 scratch each. The single-beam twin (208-265) used `sc.bucket` directly, so the pair version regressed on exactly the field the scratch struct carries for it. Hypothesis 3: the per-collide allocation scales linearly with the particle count. On the whole sliced collide it is ~48 B/particle at one rank (below the undivided CPU route's ~87 B/particle, which gathers slice states per collide), so this is a performance lead (class 15), not a parity one. At the production point held on one rank (~900k particles) the migration alone would be ~27 MB per collide, above the 0.004-0.011 GiB per collide `docs/experiences.md:362-366` quotes for the pooled collide (measured there at 16+ ranks, where the per-rank share is smaller).
Repro: `julia --project=/cfs/ad/dxu/Library/Julia/Octopus --threads=4 /cfs/ad/dxu/Library/Julia/Octopus/result/comprehensive_audit_2026_10_18/probes/U5/alloc_migration.jl` prints `migrate_in_bytes=1171152` at `N_per_beam=20000` and `4803920` at `80000` (4.10x for 4x the particles), with `two_beams_push_bytes=843648` and `3516384`. Whole-collide table from `alloc_collide.jl` (steady state, grid 32):

| ns | N/beam | sliced batched | sliced dataflow | CPU undivided |
|---|---|---|---|---|
| 5 | 20k | 3,649,400 B | 3,917,000 B | 5,081,912 B |
| 5 | 80k | 9,413,136 B | 9,682,400 B | 15,576,960 B |
| 15 | 20k | 12,872,424 B | 21,046,848 B | 12,212,264 B |
| 15 | 80k | 16,580,264 B | 24,751,424 B | 20,975,528 B |

(the ns-scaling of ~46 KB per pair batched / ~86 KB per pair dataflow is task-spawn and per-pair bookkeeping garbage shared with the CPU route, not sliced-specific).

### LEAD U5-3 [Minor, confidence high] src/tasks/strongstrong/pic_cpu_sliced.jl:208
Claim: `_pic_sliced_migrate_in` (208-265) and `_pic_sliced_migrate_out!` (468-496) have no caller anywhere in the repository: two hand-maintained twins of the pair migration that no pin touches and that already differ from it (they pool the per-beam bucket, the pair version does not -- LEAD U5-2).
Mechanism: `_sliced_collide!` (2150, 2216) and `spectral_sliced.jl` (727, 783) call only the `_pair_` forms. Defect class 2 (duplicated knowledge that drifts) and 13 (code no test can fail): a future edit to the migration protocol has two places to land and one of them is silent.
Repro: `grep -rn "_pic_sliced_migrate_in(\|_pic_sliced_migrate_out!(" /cfs/ad/dxu/Library/Julia/Octopus/src /cfs/ad/dxu/Library/Julia/Octopus/test /cfs/ad/dxu/Library/Julia/Octopus/validation /cfs/ad/dxu/Library/Julia/Octopus/examples /cfs/ad/dxu/Library/Julia/Octopus/profiling | grep -v "^.*:function "` prints nothing.

### LEAD U5-4 [Minor, confidence high] src/tasks/strongstrong/pic_cpu_sliced.jl:2222
Claim: The non-finite refusal reports rank-pair incidences as "slice pair(s)": every rank involved in a bad pair increments its own `nbad` and `_mp_global_count` sums them, so one bad pair at P ranks is reported as |G1| + |G2| + (non-member owners) pairs.
Mechanism: `pr.bad && (nbad += 1)` (1264) and `c.nbad += 1` (1913) run on every member and owner of the pair; `nbad_all = _mp_global_count(nbad)` (2222) sums over ranks; the message (2224) says "$(nbad_all) slice pair(s) met a non-finite coordinate (this rank held $(nbad) of them)". At one rank the count is exact, which is the only regime the suite pins. Loud, so not a silent defect; a wrong number in a refusal message (class 6/14).
Repro: by reading; a 2-rank run with 3 whole slices per beam where one slice holds a NaN gives `nbad_all = 2` for one pair (both ranks are members or owners, owners being `(0, 1)`). Durable check: `grep -n "nbad += 1\|c.nbad += 1\|_mp_global_count(nbad)" src/tasks/strongstrong/pic_cpu_sliced.jl`. Not executed (needs the launcher).

### LEAD U5-5 [Minor, confidence med] src/tasks/strongstrong/pic_cpu_sliced.jl:878
Claim: The threaded-deposit fold branch that exists for the sliced route -- `charge .+= view(local_grid, axes(charge)...)` in `_pic_deposit_drifted_threaded!` (`pic_cpu.jl` 2413-2418), folding padded chunk grids into the nx x ny plane `_pic_sliced_deposit!` passes -- is reached by no test in the suite; it is sound here, measured bitwise against the CPU collide at 80k particles per slice.
Mechanism: `_pic_deposit_parallel(n, nx, ny)` needs `n >= 160 * nx * ny` (`interface.jl` 659-666), i.e. 40,960 particles per slice at grid 16. The one-rank pins run 256/192 particles (`runtests.jl` 22430-22434) and the launcher fixtures' largest PIC beams are 98,304/81,920 with 3 slices (`test/mpi_seam_check_fixture.jl` 244-253: ~32k per slice at one rank, less per rank when divided), so every pinned sliced run takes the serial deposit. The branch was added with a comment arguing bit-identity rather than a test showing it (class 13: a sweep never fed its case). Hypothesis 1's "same bits on both routes" was therefore only ever asserted below the threshold.
Repro: `julia --project=/cfs/ad/dxu/Library/Julia/Octopus --threads=4 /cfs/ad/dxu/Library/Julia/Octopus/result/comprehensive_audit_2026_10_18/probes/U5/bitwise_threaded_deposit_big.jl` prints `deposit_parallel(N/5, 16, 16)=true` and `bitwise=true` for `default` and `tsc` on both loops (luminosity `9.784450333497815e18, 1.0883669847331643e19` on both routes). Coverage check: `grep -n "Beam(" test/mpi_seam_check_fixture.jl` (max 98304) and `grep -n "_PIC_DEPOSIT_PARTICLES_PER_CELL = " src/tasks/strongstrong/interface.jl` (160).

### LEAD U5-6 [Minor, confidence high] src/tasks/strongstrong/pic_cpu_sliced.jl:1037
Claim: Under `green_cache = :none` the sliced route copies the whole 2nx x 2ny complex Green table once per pair per direction per collide -- 126 MB per collide at grid 64 with 225 pairs, where the undivided CPU route allocates 5.6 MB -- and the cost grows with grid x pairs, ~470 MB per collide at grid 128.
Mechanism: `_sliced_owner_grids!` must hold the table across the stage boundary between the grids hop and the solve, and with no cache `_pic_slice_pair_green!` returns the workspace's own table, so `green_fft === workspace.green_fft && (green_fft = copy(green_fft))` (1037) copies it; the CPU route solves immediately and never copies. Performance (class 15), non-default option, measured.
Repro: `julia --project=/cfs/ad/dxu/Library/Julia/Octopus --threads=4 /cfs/ad/dxu/Library/Julia/Octopus/result/comprehensive_audit_2026_10_18/probes/U5/alloc_green_none.jl` prints, at `grid=64`, `green_cache=none route=sliced steady_bytes=126460440 per_pair_bytes=562046` (= 2 x 262,144 + bookkeeping) against `route=cpu_undivided steady_bytes=5579832` and `green_cache=slice_pair route=sliced steady_bytes=27621952`.

### LEAD U5-7 [Minor, confidence high] docs/design/multi_process_policy.md:471 (out of region: documentation of this file's protocol)
Claim: The Step 4d narrative describes a protocol the code no longer runs: it says the coordinator sends the reduced record "to every rank involved in the pair -- members and plane owners -- each of which forms the same grids from the same numbers", and that "each PLANE ... has an OWNER"; the code sends the reduced record to two per-DIRECTION owners only, which form the grids and send a nine-number grids message to the members.
Mechanism: `_pic_collide_sliced!` sends `pr.reduced` to `pr.owner[d]` for d in 1:2 (the `_PIC_TAG_REDUCED` sends, 1217 and 1863) and the owners send `g` under `_PIC_TAG_GRIDS` to `_pic_sliced_members(g1, g2)` (1244 and 1881); `owner = ((2(q-1)) % P, (2(q-1)+1) % P)` (1143, 1745) deals one owner per direction, all planes of that direction included. The 4d history record (`docs/history/multi_process_step4d_sliced_2026_09_05.md:32`, "reduced record to the two direction owners") is accurate; the design note's section was not updated when the owner hop was added (class 14).
Repro: `grep -n "every rank involved in the pair\|each PLANE of the pair" docs/design/multi_process_policy.md` (lines 452, 471-472) against `grep -n "_PIC_TAG_REDUCED + d - 1\|_PIC_TAG_GRIDS + d - 1" src/tasks/strongstrong/pic_cpu_sliced.jl` (reduced: to `pr.owner[d]`; grids: owner to members).

## Clean

Hypothesis 1 (same particle, same slice, same weight on both routes):
- Membership is not re-derived: both routes consume the same `longitudinal_slices` result (`pic_cpu.jl` 138-139); the slice index travels with the particle in row 7 of the migration columns (`cols[7, c] = T(s)`, 350) and `starts`/`bucket` invert it exactly (the end-of-bucketing check at 414-415 errors on any stray column). `param` tuples (1146-1149, 1747-1750) are built from `weight[i], boundary[i], center[i], boundary[i+1]` exactly as `_pic_collide_pair!` (`pic_cpu.jl` 413-416) and as the theory note states (`slice_longitudinal_interpolation.md` 143-144). `weight` is carried and read by NOTHING on either route (`grep -n weight` over both files: only the tuple constructions) -- "same weight" is vacuous but consistent: the slice's charge enters through its member count, identically on both routes.
- Leaves compared line by line with `_pic_interaction!` (`pic_cpu.jl` 1130-1370): source record (sL/sR, first-member or origin shift, min/max over both drifts, shifted sums, count 2n), field record (drift S = (z - c)/2 computed without writing, count n, same origin form `x + (0.5(z - c)) px`), the fold (max of negated minima, sums in group rank order, first member from the group's first rank = the slice's globally-first member by the layout's prefix rule), `_pic_sliced_extents` (same `_pic_axis_extent` arguments per role and axis), grids (same `_pic_interaction_grids` and `_pic_slice_pair_green!` arguments, cache key `(i, j, d)`), deposit (plane zeroed then deposited = the CPU's `fill!(charge, 0)` plus direct deposit; the owner's `interior .+= partial` adds to zero), solve (same `spectral .= charge; fft; .*= green_fft; ifft; real`, same `hx = width/(nx-1)`), kick (same drift, same `pz -= 0.25(px^2+py^2)`, same `_pic_apply_kick_range!`/`_quadratic_range!` arguments, same `kick_scale = 2 kbb`, same `_slice_interpolation_parameters(lb, rb)`), virtual positions (same `sM`, read before any kick of the part), luminosity (mesh from the min/max over BOTH beams' virtual positions, same `_pic_deposit!` call on `(lnx+1) x (lny+1)`, same overlap sum times `klum * hxi * hyi`). Measured: bitwise equal to the undivided CPU collide on both loops at 20k/beam ns=15 grid 32 (six option routes), at 24k per slice (kick maps threaded), and at 80k per slice grid 16 (deposit threaded) -- the suite's pin extended from 256/192 particles into the threaded regime.
- Order and gates: `collision_pair_batches` and `_slice_collision_order` sort the same keys with the same algorithm (`slicing.jl` 703-800); the dataflow gate is read from `order` (1691-1708). `deal_of` and `canon` enumerate the same sorted tuples, so both loops deal the same owners (verified bitwise, dataflow vs batched, every probe).
- Layout: 3000 random cases, 0 violations (table above); the `P > ns` largest-remainder loop saturates correctly when N < P (break on `s == 0`) and the `P <= ns` midpoint rule is monotone in the cumulative count.
- Tags: codes 1-25 with the plane offsets stay below 32 (`_PIC_TAG_PARTIAL + 3 + 2 = 12 < 13`, `_PIC_TAG_POTENTIAL + 3 + 2 = 18 < 19`, origins 24/25); the bound check (1109, 1759) uses the maximal tag `ns1 ns2 * 32`.

Hypothesis 2 (dropped charge, empty slices):
- Empty slices: `n1 == 0 || n2 == 0` sets `ran[p] = false` and skips (1133-1136, 1736-1739), the same decision from the same global `plan.counts` as `_pic_collide_pair!` (`pic_cpu.jl` 407-409); `lum_parts` is zero-filled per collide by the caller (`pic_cpu.jl` 195) so a coordinator change between turns cannot leave a stale pair value in the all-sum; the caller folds only `ran[p]` pairs (366-367).
- Dropped counting: source side against `source_grid` at drifts sL/sR in `_pic_sliced_deposit!` (888-892) and field side against `field_grid` after the drift in `_pic_sliced_kick!` (969-973), under `grid_extent !== :extrema` -- on this route (`:slice_pair` only, `pic_cpu.jl` 204-205) the same condition as the CPU's `ge !== :extrema || interaction_grid !== :slice_pair`; counted into `first(workspaces).dropped`, which `_pic_report_dropped(workspaces)` sums and warns on. Measured equal to the CPU route: 3 == 3 at 20k/beam ns=15 `:sigma` k=4 (pool-summed), 0 == 0 elsewhere. Members' slice indices cannot change in transit (row 7), so no charge is lost at a boundary by the migration; particles with slice index 0 stay home on both routes.
- Every non-coverage path is loud: a stray column errors (280, 415), a short return errors (448-449, 485-486), an unroutable position errors (105), the tag bound throws (Policies 1108-1115), and a non-finite record ends in the agreed throw (2219-2225) except for the split case of LEAD U5-1.

Hypothesis 3 (allocation): measured; see LEAD U5-2 (particle-count scaling, ~30 B/particle in the migration, ~48 B/particle on the whole route, below the CPU route) and LEAD U5-6 (`:none` Green copies). Pools: planes, luminosity grids, records, field workspaces and virtual positions are cursor-pooled per batch (502-569) and free-listed under dataflow (1522-1607, returned only after `_mp_test_all(pr.sends)`, 2080-2083 and 2106); the migration scratch is pooled except for the per-beam `bucket`.

Receipts (class 11): `:pic_pair_schedule` records the loop that ran (`schedule=loop`, 2196), `exchange=:sliced`, and `batch_mode` as a literal of the branch taken; `:pic_slice_layout` records the group widths and migrated counts; `:pic_slice_exchange` counts messages per kind. The loop-pin test (`runtests.jl` 22496-22513) asserts the schedule field, so neither loop can pass as the other.

Observations that are not leads: under `batch_mode = :sequential` every batch has one pair, so `q = 1` and every pair's owners are ranks `(0, 1)` -- all solves on two ranks; the design note names `:sequential` a pin arm with "two different owner deals" (`multi_process_policy.md` 621-625), so this is a documented consequence, not drift. `_sliced_needs_origin` (`:sigma` only) and the record's `ge !== :extrema` sums branch are consistent today only because `grid_extent` admits exactly `:extrema` and `:sigma` (`interface.jl` 1469-1470); a third estimator would silently fold sums about different origins across a group. The record pool (`_pic_sliced_record!`, 546-555) reallocates a slot whose requested length changes between batches; small and bounded by the pair count.

## Unchecked

- Any behaviour at P > 1: the real `_mp_exchange_columns_impl` (ext/), group folds across ranks, the `:sigma` origin hop, the dataflow loop's blocking and the hang of LEAD U5-1 were not run; the suite covers them through the launcher children (`runtests.jl` 23230-23700), which this unit did not execute. The one-rank passthrough was the only seam exercised.
- `spectral_sliced.jl` (727, 783) and `gaussian_pic.jl` share `_pic_sliced_layout`, the pair migration and the record/owner/leaf hooks: a cross-file seam, noted and not followed (LEAD U5-2 applies to spectral's collide too).
- The MPI extension's handling of the `ReshapedArray`-of-`SubArray` column matrices `_pic_mig_matrix!` produces (178-181) when they reach a real communicator: outside the region.
- `docs/theory/gaussian_longitudinal_slicing.md` was grepped for `weight` only, not read: the sliced route adds no slicing arithmetic of its own (membership, centers, weights and boundaries all come from `slicing.jl` unchanged), so the theory-vs-code question for slicing belongs to the unit holding `slicing.jl`.
- `_pic_slice_pair_green!`'s cache semantics under the owner deal (a pair's table lives on the owner the deal picks; a re-ordered batch moves it) were read but not measured; the receipts (`_pic_report_green_cache`) are the place to see it.
