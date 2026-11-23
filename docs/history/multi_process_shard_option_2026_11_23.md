# The shard rule of `MultiProcessExecutionPolicy` becomes an option (2026-11-23)

A production launch refused by design, three ways out weighed, one option added. Frozen record of
the batch that added `MultiProcessExecutionPolicy(; shard = :chunk_aligned | :balanced)`. The core
is commit `5e91b99`; the tests, the PIC (particle-in-cell) multi-process contract and this record
follow in the same batch. The design note is `../design/multi_process_policy.md` (step 3a, the seam
table, "Determinism, and what step 3 chose"); the semantics below are those of the docstrings in
`src/policies/Policies.jl`, which are the source of truth.

## 1. The trigger

On 2026-11-23 the owner's strong-strong scan on NERSC Perlmutter (the National Energy Research
Scientific Computing Center's machine; the scan itself is described in
`multi_process_exchange_leak_2026_11_23.md`), launched as `mpirun -np 128`, was refused:

> 128 ranks cannot divide the 64 fixed reduction chunks evenly, so no shard of the beam is
> chunk-aligned and a cross-rank fold could not reproduce the single-process sum bit for bit. Use a
> rank count that divides 64: 1, 2, 4, 8, 16, 32, 64.

The refusal was the step-3a design decision working as intended. The CPU (central processing unit)
reductions partition the beam into `_REDUCTION_CHUNKS = 64` fixed chunks and sum the partials in
chunk order; that order is what makes a result independent of the thread count. Step 3a gave every
MPI (Message Passing Interface) rank a contiguous run of whole chunks, so the ranks' partials,
gathered and folded in chunk order, are the single-process sum bit for bit. The price, stated when
the rule was chosen, is that the rank count must divide 64. 128 does not.

## 2. Three ways out, and why the option won

1. **A policy option, `shard = :balanced` on `MultiProcessExecutionPolicy`.** Chosen by the owner.
   A strict superset of the default: identical where the rank count divides 64, equal contiguous
   ranges with a rank-ordered fold elsewhere. Repeatable at a fixed rank count. Within the CPU/CUDA
   parity tolerance of a single process. The receipt records the rule requested and the alignment
   in force, so the configuration the code read is visible.
2. **An environment variable overriding `_REDUCTION_CHUNKS`.** Rejected. The chunk count is the fold
   order of every CPU reduction, so changing it changes single-process results bitwise and
   invalidates every digest pin. It is a hidden configuration channel outside the option schema and
   the receipts; a configuration you set is not a configuration the code read. It is a compiled
   constant. And it only ever admits the divisors of the new count.
3. **A chunk-count policy option.** Rejected for the same bitwise ripple through every CPU
   reduction and the same divisor limitation.

No other policy needs an option. The CPU threads policy already runs at any thread count with
identical bits; that is what the fixed chunks buy. The CUDA policy's reductions are judged against
the CPU at a tolerance, not bitwise. Only the multi-process policy cuts particles into rank shards.

One fact made the cost small for the case that triggered it. The design note already places the
PIC collide's per-slice folds in the tolerance class at any rank count above one (they are keyed
by slice membership, which is per-turn data), so for a strong-strong run the relaxed shard moves
only the whole-beam moments and the luminosity in the last bits.

## 3. The semantics

`MultiProcessExecutionPolicy(; threads = :auto, ranks = :auto, shard = :chunk_aligned)`; positional
`(threads, ranks, shard = :chunk_aligned)`. `shard` must be one of
`Octopus._MULTI_PROCESS_SHARD_RULES = (:chunk_aligned, :balanced)`; anything else is refused by
name (`ArgumentError("shard must be one of (:chunk_aligned, :balanced); got ...")`).

| rule | rank count divides 64 | rank count does not divide 64 |
|---|---|---|
| `:chunk_aligned` (default) | each rank owns a contiguous run of whole chunks; every cross-rank fold is the single-process sum bit for bit | refused by `_mp_shard_range` with the message of section 1, which now ends "; or construct the policy with `shard = :balanced` to accept any rank count at the cost of cross-rank bit identity (results repeatable at a fixed rank count, within the CPU/CUDA parity tolerance of a single process)." |
| `:balanced` | the aligned rule, bit for bit the same shards and folds | rank `r` owns `_chunk_bounds(global_n, nranks, r + 1)`, the `r`-th of `nranks` equal contiguous ranges; every rank keeps all 64 chunks for its own reductions (`_mp_local_chunks() == 64`, `_mp_first_chunk() == 1`); `_mp_chunk_fold` sums each rank's 64 partials in chunk order to one number and the ranks' numbers in rank order, through `_mp_allsum!` (Allgather, then a rank-ordered fold) |

What stays bitwise under `:balanced` at a non-dividing rank count: the tracked beam, at any rank
count, because tracking does not reduce; a rank's result against its own thread count, because the
64 chunks within a rank are untouched; a run against itself at a fixed rank count, because the
fold is rank-ordered. What does not: the cross-rank luminosity fold (`_mp_chunk_fold` has three
callers, the strong-beam element's two luminosity sites in `src/track/strong_beam_track.jl` and the
tracking task's per-beam luminosity in `src/tasks/Tasks.jl`) agrees with a single process only to
rounding, the CPU/CUDA parity tolerance class; and the whole-beam moments move in their last bits
as the rank-ordered partial sums change their ranges, a class they were in at any rank count above
one already.

`MultiProcessContext.chunk_aligned` is the rule in force: `true` under `:chunk_aligned`, and under
`:balanced` exactly when `64 % nranks == 0` (`_mp_chunk_aligned(nranks, shard)`). The
`:multi_process_communicator` execution receipt (`execution_receipts(audit)`, the entries with
`r.consumer === :multi_process_communicator`) carries `values.shard` (the request) and
`values.chunk_aligned` (in force) beside `nranks`, `rank`, `requested_ranks`, `resolved_by` and
`threads`.

## 4. Touch points (commit `5e91b99`)

- `src/policies/Policies.jl`: the policy's `shard` field, both constructors and
  `_MULTI_PROCESS_SHARD_RULES`; `MultiProcessRequest(ranks, shard)` with the one-argument
  constructor kept; `MultiProcessContext(comm, nranks, rank, ranks, resolved_by, shard,
  chunk_aligned)` with the five-argument constructor kept (defaults `:chunk_aligned, true`);
  `_mp_shard_range(global_n, nranks, rank; shard)` and `_mp_shard_verdict(counts, nranks; shard)`;
  `_mp_chunk_aligned(nranks, shard)`; `_mp_resolve_shard`, which reads the rule from the context
  and names it in its mismatch message; `_mp_first_chunk`, `_mp_local_chunks` and `_mp_chunk_fold`,
  which branch on the alignment in force; the `shard` entry of the option schema (`Symbol`, default
  `:chunk_aligned`, consumer `:multi_process_communicator`, backend `CPUThreadsBackend`) and the
  `:shard` entry of `configuration_report(policy)` (status `:unresolved`, because the alignment in
  force depends on the communicator's rank count, read at activation).
- `src/beam/Beam.jl`: `_resolve_execution_policy` and `_prepare_beam_initialization` build
  `MultiProcessRequest(policy.ranks, policy.shard)`, so `Beam(N, policy, ...)` shards the drawn beam
  by the same rule; `_open_multi_process_context` computes the alignment in force and records
  `shard` and `chunk_aligned` in the receipt; the `Beam` docstring states both rules.
- `validation/multi_process_memory/repro_exchange_leak.jl`: the reproduction script of the
  exchange-leak record reads `REPRO_SHARD`, which is how the three-rank measurement below was made.
- The rest of the batch, after the core: the tests, the PIC multi-process contract
  (`StrongStrongPICMultiProcessConsistencyContract`, whose own rank-count check admits only the
  divisors of 64 on the core commit), the design note, `docs/current_runtime.md`,
  `docs/public_api.md`, `docs/todo.md` and this record.

## 5. Measurements on the main checkout

Made on the core commit under MPICH_jll's `mpiexec`, before the tests of this batch existed:

- At 3 ranks the default refuses by name (the message of section 1 with the new ending), and
  `shard = :balanced` runs the owner's strong-strong case end to end: 60 turns, 12,000 electron and
  4,800 proton macroparticles (whole-beam counts), 2 Julia threads per rank, exit 0 (wall 180.8 s;
  the logs are in the git-ignored `result/oom_repro/J_balanced3/`).
- The existing two-rank MPI child is green on the new core.
- `validate_configuration_metadata()` is `true`.
- The registry snapshot is unchanged.

Not measured here: the size of the luminosity's deviation from the single-process value under
`:balanced` at a non-dividing rank count, and the option's effect on the moment rows. Those numbers
belong to the tests of this batch and to the section below.

## 6. Gate and further measurements

[INTEGRATOR: gate and measurement lines]
