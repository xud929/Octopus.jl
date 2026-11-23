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
- `src/policies/Policies.jl`, `src/track/strong_beam_track.jl`, `src/tasks/Tasks.jl` (fix
  `d11c25b`, the tests unit): `_MPChunkGrid`, `_mp_chunk_grid(rep)` and
  `_mp_chunk_local_bounds(grid, chunk)` beside `_mp_chunk_fold`, and the three weak-strong
  luminosity loops (`_track_thin_strong_beam!`, `_track_gaussian_strong_beam!`,
  `_track_fused_luminous!`) read their chunk bounds from the grid; see section 6 for the defect.
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

### Further measurements

Made on the core commit with the reduced reproduction of the owner's scan case
(`validation/multi_process_memory/repro_exchange_leak.jl`, `REPRO_SHARD=balanced`) under MPICH_jll's
`mpiexec` on acnlinj4 (64 cores, 128 hardware threads, 503 GB); the logs and artifacts are in the
git-ignored `result/oom_repro/K_balanced/`:

| run | ranks x threads | macroparticles (whole beam) | turns | result |
|---|---|---|---|---|
| K6 | 6 x 2, `shard = :balanced` | 320,000 + 128,000 | 300 | exit 0; 695.5 s wall, 2.32 s per turn (the aligned 8-rank run D of the leak record, same beams: 578.5 s, 1.93 s per turn); peak RSS 2.02 to 2.21 GB per rank, 12.8 GB in total, flat from turn 30 on; 4 exchange-buffer entries (17.6 MiB) per rank |
| K128 | 128 x 1, `shard = :balanced` | 64,000 + 25,600 | 30 | exit 0; 196.7 s including the start of 128 processes on 64 cores (a functional check, not a timing); peak RSS 1.96 GB on rank 0 and 238 GB in total, which is the per-process baseline of the sysimage, the compiled package and MPI at 128 copies; 4 exchange-buffer entries per rank |

Physics beside the aligned reference. An aligned 6-rank run does not exist by construction, so K6
is compared with the aligned 8-rank run D (the same beams, seed and turns) with
`result/oom_repro/K_balanced/compare_relative.py`; the outputs are the `compare_*_vs_D_fixed.txt`
files beside the K6 log. The comparison therefore carries two effects at once: the reassociation of
the balanced fold and the rank-count dependence of the PIC per-slice folds, which was already in the
CPU/CUDA parity tolerance class at any rank count.

- Luminosity: bitwise identical at turn 0; the two series then separate to a maximum relative
  difference of 1.8e-10 (turn 281) and stand 8.7e-12 apart at turn 299.
- Moments at turn 0: every row of both beams agrees to 1.4e-11 relative or better, most rows to
  1e-15 to 1e-13.
- Moments over 300 turns: the six diagonal second moments of both beams stay within 2.2e-10
  relative; the worst rows are the electron beam's small cross moments (`m100001`, `m010010`,
  `m100010`), whose deviation reaches 7e-8 of the row's median magnitude at turn 252; every proton
  row stays within 3.4e-9 of its median magnitude.

That is the CPU/CUDA parity class the design note predicted for a non-aligned shard, amplified over
300 turns by the beam-beam dynamics; nothing in it is specific to `:balanced` beyond the turn-0
reassociation.

### The defect the tests unit found in the core

The core commit made `_mp_first_chunk()` and `_mp_local_chunks()` return `1` and `64` under a
balanced shard that is not chunk-aligned, meaning "no global position; chunk the local range".
Their only three callers, the weak-strong luminosity loops named in section 4, read the two
numbers as a position on the GLOBAL 64-chunk grid and subtracted the shard offset, which the
comment above each loop argued for ("the local partition IS the global one"). Under
`OCTOPUS_MPI_CHECK_SHARD=balanced` at `mpiexec -n 3` the suite's MPI child died in
`_track_gaussian_strong_beam!` with `BoundsError: attempt to access 85-element Vector{Float64}
at index [-84]` on rank 1 and `86-element ... at index [-169]` on rank 2: every rank walked all
64 global chunks minus its own offset. The strong-strong solvers chunk the local range
everywhere and never read the accessors, which is why the owner's case, the three-rank run of
section 5 and K6/K128 ran to completion; the core commit's own checks exercised only that path.

The fix (`d11c25b`) is one helper beside the fold it feeds: `_mp_chunk_grid(rep)` resolves the
shard and the alignment in force once per call site, and `_mp_chunk_local_bounds(grid, chunk)`
returns LOCAL bounds in both cases (the global partition through the offset under an aligned
shard, bit for bit what the loops computed before; the same fixed partition of the local range
otherwise). Measured with it: the 1-rank and 2-rank children (default and balanced) print
receipts bitwise identical to the unfixed tree's; at 3 balanced ranks the child runs end to end
with the weak-strong luminosity 2e-16 relative to the single-process value (the rank-ordered
fold) and the tracked shards bitwise. The testset "The reduction chunk grid follows the alignment
in force" pins the rule on hand-built grids and holds the three call sites to the helper by a
source scan; the launcher testset's three-rank balanced launch is the regression test that failed
unfixed. The lesson is in `docs/experiences.md` ("A new case in an accessor's return is a rename
for its callers").

### The tests and the contract units

The batch's units were implemented by three subagents in worktrees off the core commit and
replayed onto `main` in this order: the docs unit (`68e1ece`), the contract unit (`b6de0c2`,
merged as `3d7a77a`), the consumer fix (`d11c25b`) and the tests unit (`953686a`); the last two
are the tests agent's commits replayed onto the merged tree, whose content is identical to the
agent's own merge of `main`.

The tests unit (`953686a`): the serial testset "A balanced shard accepts any rank count and is the
aligned rule where that divides the chunks" (484 tests: both rules by name, the superset property
at every divisor of 64, the balanced partition at 3, 5, 6, 7, 12, 96 and 128 ranks against
`_chunk_bounds`, the refusal message, `_mp_chunk_aligned`, the balanced verdict, the request and
context constructors, the schema entry, both configuration reports, the passthrough receipt, and
the chunk bookkeeping under hand-built contexts); the MPI child reads `OCTOPUS_MPI_CHECK_SHARD`,
builds every policy through one helper, checks the communicator receipt against the request and
prints `MPI-SHARD rank= nranks= shard= chunk_aligned= OK` on every rank (the step-3a offset line
is `MPI-SHARDOFFSET` now); the launcher testset gains three launches: three ranks balanced (must
succeed: tracking shards bitwise equal to the single-process reference, `MPI-LUM` the same bits
on every rank and within 1e-12 of the reference but not bitwise, every strong-strong receipt at
the existing 1e-12), two ranks balanced (receipts equal to the two-rank default's to the
character apart from the `MPI-SHARD` line and the `MPI-PICFLOW` timing statistics: the superset
end to end) and three ranks default (must fail with "cannot divide the 64 fixed reduction
chunks", one `MPI-CHECK FAIL` line per rank and nothing that says OK). Hand runs under
MPICH_jll's `mpiexec`: 1 rank 239 s, 2 default 361 s, 2 balanced 359 s, 3 balanced 329 s, 3
default refused in 9 s. The balanced shards of the fixture's 256 particles over three ranks are
1:85, 86:170 and 171:256 (`_chunk_bounds` uses `fld`), and nothing in the tests hand-copies them.
The extracted launcher testset on the merged tree: 2688 of 2688 in 21 min.

The contract unit (`b6de0c2`): `StrongStrongPICMultiProcessConsistencyContract(; shard)` with
the divisor refusal under `:chunk_aligned` only, `shard` carried to the child by a declared
launch-field list and parsed back by the contract's own field type, the child recording the rule
requested and in force and the parent failing a leg whose record disagrees; contract runs
`(1, 2)` default (266.9 s, first run with precompilation) and `(1, 3)` balanced (91.1 s) both
pass with the CUDA leg, the three-rank luminosity 2.05e-15 relative to the one-rank value, which
is the two-rank default's class (1.92e-15). The suite's launcher testset runs the `(1, 3)`
balanced contract with `cuda = false`.

Two notes for the next session. Running the launcher testset extracted needs `MPICH_jll`, a test
target and not a project dependency: bind it in an `OCTOPUS_EXTRACT_PRELUDE` file
(`const MPICH_jll = Base.require(Base.PkgId(Base.UUID("7cb0a576-ebde-5e09-9194-50597f1243b4"),
"MPICH_jll"))`) or the block reports one `@test_broken` and skips the seam; `run_ranks` now hands
the child `JULIA_LOAD_PATH = join(Base.LOAD_PATH, ":")`, which is the same string under
`Pkg.test`. And a pre-existing warning, not of this batch: with `validate_configuration_metadata()`
and the PIC multi-process contract in one process, the counter RNG reports `rng_id 1 ... already
held by a bpm_observer consumer` (`src/math/counter_rng.jl`); observed by the contract unit, not
investigated.

### Gate

[INTEGRATOR: gate lines]
