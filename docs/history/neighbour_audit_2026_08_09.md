# Targeted Neighbour Audit — the 2026-08-09 CPU-threading campaign

Per the standing owner directive and
[`docs/comprehensive_audit.md`](../comprehensive_audit.md) ("The targeted
neighbour audit"): after a fix campaign, re-walk each fix's call sites and
sibling surfaces, and re-run the property the fix was about on the neighbours
it did not change.

Campaign audited: `64169ca`, `9e8e121`, `e2bc768`, `4536403` (+ the docs commit
`52f09f4`). Measurements in
[`cpu_threading_2026_08_09.md`](cpu_threading_2026_08_09.md).

The campaign's diff touches three surfaces beyond the two solvers it optimized:
`_run_logical_workers` (exception unwrapping), `ExecutionAudit` (a lock) and
`_PICSlicePairGreenCache` (a lock field). Everything reachable from those was
re-walked.

## What batching newly depends on, and what was checked

Running slice pairs concurrently changes which properties are load-bearing. The
sequential loop tolerated things a concurrent one does not, so the audit was
organised around that difference rather than around the diff's line count.

| property | status | evidence |
|---|---|---|
| Slice index sets pairwise disjoint | **clean, now pinned** | Two pairs in one batch write different slices of the same beam. An overlap would be a data race, where sequentially it would only have been wrong physics. Measured 0 duplicates and full coverage for `:equal_area`, `:equal_count`, `:equal_width`, `:normal_quantile`, on continuous z AND on z quantized to heavy ties — the `:equal_count` tie-splitting case (audit part 6, R2) is where an overlap would come from if one ever did. Nothing pinned this; a suite test now does. |
| Global lattice-Green memo | clean | `_PIC_LATTICE_GREEN_CACHE` is already guarded by `_PIC_LATTICE_GREEN_LOCK`. Its eviction point moves with the schedule, but `_pic_lattice_green_table` is deterministic in `(nx, ny, rho-key)`, so a re-computed entry is the same table and results cannot move. |
| Per-pair workspace exclusivity | clean, after one fix during the campaign | Every buffer is fully overwritten before it is read. The `Core.Box` that briefly shared ONE workspace across all workers was caught by the permanent tripwire and is recorded in the campaign note. |
| Green cache concurrent access | clean | Distinct `(i, j, direction)` keys per pair, and the lock covers lookup and insert but not the rebuild. Each key's hit/miss/rebuild sequence is the sequential one. |
| `:quadratic` reaches the batched path | clean | "PIC slice_interpolation flag" runs `nslices=3` through public `collide!`; at the gate's `--threads=4` the pool is 3, so it batches. `workspace.mid` is per workspace. |
| `:node` reaches the batched path | clean | The CUDA-vs-CPU route sweep runs `interaction_grid=:node` on CPU at `nslices=3` (pool 3, batched) and compares to CUDA at `< 1e-13`. |
| `:source_slice` must NOT batch | clean, pinned | `_pic_batchable` returns false and the run's own receipt is asserted to say `:sequential`. |
| Nothing depended on the `CompositeException` wrapper | clean | Zero hits for `CompositeException`/`TaskFailedException` across `src/`, `test/`, `validation/` before the change. |
| `_pic_report_dropped` dispatch | clean | The CUDA reporter is a distinct name (`_cuda_pic_report_dropped(::_CUDAPICWorkspace)`); no method collision. |
| Sibling solvers unaffected | clean | spectral and soft-Gaussian re-measured against the baseline: bit-identical digests, times within noise. Recorded in the campaign note. |

## Findings and dispositions

**F1 — `_pic_cpu_workspace!` left orphaned. Fixed.** Both callers moved to
`_pic_cpu_workspace_pool!`, leaving a function with no call site anywhere in
`src/`, `test/` or `validation/` — and a docstring still describing it as the
live path ("one workspace serves every thread setting"). Harmless to run,
misleading to read. Deleted, following the precedent of the `_default_rng`
removal in the 2026-08-08 session. This is the "grep the whole tree" rule
applied in the other direction: the campaign checked that nothing still CALLED
the old helper and did not check whether anything still DEFINED it.

**F2 — the pair-worker count came from the pool, not the policy. Fixed.**
`_pic_cpu_workspace_pool!` only ever grows, so `length(workspaces)` is the
high-water mark of every policy the label has run under. Both collide loops
scheduled off it directly, so a pool grown to 15 by one run would keep spawning
15 pair workers after a caller asked for 2 — a configuration set and not read,
which is the exact failure class AGENTS.md names. `_pic_collide!` and
`_gpic_collide!` now compute `pool_workers = min(length(workspaces),
_pic_pool_size(solver))` and index the pool only up to it.

Reachability, stated rather than assumed: `StrongStrongTask.policy` is an
immutable field of an immutable struct and `execute!` always scopes from it, so
the public task path cannot change the policy between runs on one
`runtime_cache` — this was latent there. It was reachable through
`_pic_collide!` directly, which tests and `validation/` do call. Pinned with a
test that hands eight workspaces to a one-worker policy and asserts the run
reports `:sequential`.

**F3 — the disjointness property was unpinned. Fixed** (row 1 above).

## Re-measured after the fixes

Digests unchanged from the pre-campaign baseline: PIC `0xc8af3cf19999b79c`,
GaussianPIC `0x967d4e7aecddbba5` (quarter-size point, 1 and 16 threads).

## One negative result worth keeping

The campaign note says the batch width caps parallelism at 15 for 15 slices.
That understated it, and the owner caught it: a wavefront's widths are a
**triangle** — 1, 2, ..., 15, ..., 2, 1 — so 225 pairs take **29 batches of
mean width 7.76**, and the narrow ones at each end leave most of the machine
idle. Measured utilisation of pair-level parallelism alone: 51.7% at 15
workers, 24.2% at 32, 12.1% at 64. **29 serial-equivalent units is a hard
floor** — it is the dependency chain (each slice must meet all 15 partner
slices in order), not the batch barrier, so no scheduler can beat it.

The obvious remedy — divide the machine by THIS batch's width instead of by the
pool, so a width-1 batch gets all threads for its per-particle maps — was
implemented and **measured worse**, and reverted: PIC at 16 threads went
4.20 → 5.41 s, and 64 threads only 7.57 → 6.96. The reason is Amdahl inside a
pair, not the schedule: after fixes 1 and 4 the per-particle maps are only
~5–10% of a pair's work, while the Green build (23%), the field solves (20%)
and the slice gather/scatter (41%) are all still serial per pair. Giving a
narrow batch more threads therefore buys ~1.1x on a tenth of the work and pays
spawn overhead for it.

So the route to using more than ~15 threads is not a scheduling change: it is
parallelizing the serial blocks *inside* a pair. That is the next work item,
and it is the same work that removes the 6.3 GiB/collide.
