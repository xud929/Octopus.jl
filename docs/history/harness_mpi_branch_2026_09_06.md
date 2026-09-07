# The harness MPI branch: closing the production benchmark's reproducibility gap — 2026-09-06

The production benchmark
([`production_benchmark_2026_09_06.md`](production_benchmark_2026_09_06.md))
timed all four solvers across CPU threads, MPI and CUDA, and recorded that its
MPI arms had not run the repository's files: neither `test/examples` harness had
a multi-process option, so those arms went through scratch copies carrying a
six-line branch that wrapped the CPU policy in a
`MultiProcessExecutionPolicy`. The scratch copies are not in the repository, so
the MPI half of that table was not reproducible from it. This is the branch
that closes the gap, and the traps found while landing it.

## The spelling, corrected

That record and the multi-process todo row both call the switch `OCTOPUS_MP`.
The shipped name is **`OCTOPUS_USE_MPI`**. `OCTOPUS_MP` was only ever what the
throwaway scratch copies used; the harness vocabulary is already
`OCTOPUS_USE_GPU`, and one keyword with one meaning beats a second spelling for
the same idea. The benchmark record is not edited — `docs/history/` is frozen by
AGENTS.md, add-never-rewrite — so the correction lives here and in the todo row.

## The trap: a package extension does not attach to an `include`d module

Both harnesses load Octopus by `include`ing `src/Octopus.jl` into `Main`.
`MultiProcessExecutionPolicy` reaches a real communicator only through the
`OctopusMPIExt` package extension, and a package extension attaches only to a
**package**. Measured on this tree, one probe, both load orders:

| load of Octopus | `Base.PkgId(Main.Octopus)` | `Base.get_extension(Main.Octopus, :OctopusMPIExt)` |
|---|---|---|
| `include("src/Octopus.jl")` | `Base.PkgId(nothing, "Main")` | `nothing` |
| `using Octopus` | the package's own id | `OctopusMPIExt` |

So an `OCTOPUS_MP`-style branch bolted onto the harness as it stood would have
built a `MultiProcessExecutionPolicy` in a process where the seam runs its
serial passthrough: with `ranks = :auto` that is a legitimate communicator of
one, and `mpiexec -n 8` becomes eight identical whole simulations racing on one
artifact path — exit 0, plausible timings, wrong answer. The switch therefore
loads Octopus **as a package** and asserts the extension attached.

Two guards, both measured:

- With `OCTOPUS_USE_MPI=1` the harness asserts
  `Base.get_extension(Main.Octopus, :OctopusMPIExt) !== nothing` after the load
  and errors naming the consequence if it is `nothing`.
- If `Main.Octopus` is ALREADY an `include`d module when the switch is on,
  Julia 1.12 makes `using Octopus` a hard error — `importing Octopus into Main
  conflicts with an existing global` — which is loud but says nothing about the
  cause. The harness detects that case first (`Base.PkgId(Main.Octopus).uuid ===
  nothing`) and explains it.

The library's own `_launcher_rank_count` tripwire
(`src/policies/Policies.jl`) is the third guard and predates this work: it
reads `PMI_SIZE`, `OMPI_COMM_WORLD_SIZE`, `MPI_LOCALNRANKS`, `PMIX_SIZE`,
`MV2_COMM_WORLD_SIZE` and `SLURM_NTASKS`, and throws when the launcher
announces a size the communicator does not have. The harness assertion is not a
replacement for it: it fires EARLIER (at load, before beam construction) and
names the actual cause, and it covers a launcher whose variable is not in that
list.

## What the branch is

Both harnesses, the same keywords in each:

- `OCTOPUS_USE_MPI=1` — one Octopus process per rank. Read BEFORE the Octopus
  load, because it decides how Octopus is loaded.
- `OCTOPUS_CPU_THREADS` — the per-rank logical-worker count, the same keyword
  and the same `auto` default the threads-only arm reads.
  `MultiProcessExecutionPolicy` composes `CPUThreadsExecutionPolicy(threads)`
  unchanged.
- `OCTOPUS_RANKS` — passed straight through as the policy's `ranks`, with no
  harness logic: the policy already rejects a communicator of a different size,
  so naming the count is the free way to assert what the launcher started.
  Default `auto`.
- `OCTOPUS_USE_GPU=1` together with `OCTOPUS_USE_MPI=1` is an error rather than
  a silently dropped switch: the multi-process policy composes the CPU policy
  and is CPU storage only.

## Three defects found in the weak-strong harness while wiring it

The strong-strong harness had all three fixed by the 2026-08-05_b audit; its
twin never got them, which is the "a fix's neighbours" invariant demonstrating
itself.

1. **The policy was built and discarded.** `TrackingTask(line_specs; artifact =
   ...)` carried no `policy`, so `task.policy === nothing` and `execute!`
   resolved a FRESH default. The policy built from the environment reached only
   `Beam(...)`. This is the U21-17 shape, and for the MPI branch it is fatal
   rather than cosmetic: an inferred default is a `CPUThreadsExecutionPolicy`,
   so every rank would have tracked the whole beam, silently. Now `policy =
   policy`.
2. **`OCTOPUS_USE_GPU` used the pre-U21-16 grammar** (`== "1"`), so
   `OCTOPUS_USE_GPU=true` and `=yes` — the words that enable every other flag
   in these harnesses — ran on CPU. `env_bool` is now in both files.
3. **`OCTOPUS_CPU_THREADS` was not read at all**, so the only thread count the
   weak-strong harness could run at was the process default.

## What each rank writes

Under MPI every rank runs the whole file, so the branch decides line by line
which repetition is correct:

- Every rank prints its configuration dump behind an `mpi_rank = r of P` line.
  Deliberately not root-gated: each rank asserting the configuration it
  actually read is this repository's "assert what the run recorded" rule.
- `turn_timings_seconds` is per-rank — each rank's own wall clock is real data
  — but the `OCTOPUS_TURN_TIMING_PATH` TSV is written by rank 0 alone. One path
  and P writers is a race; one path and one writer is not.
- The run artifact is rank 0's already, gated inside the library
  (`src/tasks/RunArtifact.jl`).
- The `rms` lines are labelled `(rank r shard of P, not the whole beam)`
  whenever `P > 1`. `beam_statistics` is a purely local reduction — no
  collective, no shard argument — so under MPI it describes a shard. A reader
  comparing an MPI run's rms against a threads-only run's would otherwise be
  comparing a shard with a beam and calling the difference physics. At one rank
  the shard IS the beam, so the qualifier is keyed on the communicator's size
  and does not appear.

The rank for all of this comes from `MPI.Comm_rank(MPI.COMM_WORLD)`, **not**
from Octopus's `_mp_is_root()`. That code runs after `execute!` has closed its
policy scope, where the collectives read the serial passthrough and
`_mp_is_root()` returns `true` on every rank — silently
(`docs/experiences.md`, "A collective outside its scope is a silent no-op").

## Measurements

Julia 1.12.4, the shared 128-core node. MPI.jl binds MPICH 5.0.1 from its jll
artifact; the launcher is that artifact's own `mpiexec`, not the MPICH 4.1.1
Hydra on `PATH`.

**The default path is untouched.** Each harness was run at its shipped defaults
from `HEAD` and from the working tree, four threads, and the reported output
compared:

| harness | pre-change vs post-change at defaults |
|---|---|
| `test/examples/weak_strong_tracking.jl` | identical, every digit |
| `test/examples/strong_strong_tracking.jl` | identical, every digit |

**One-rank MPI reproduces the threads-only policy.** `OCTOPUS_USE_MPI=1` with
no launcher, against the threads-only run of the same tree, four threads:

| harness | threads-only vs one-rank MPI |
|---|---|
| `test/examples/weak_strong_tracking.jl` | identical, every digit |
| `test/examples/strong_strong_tracking.jl` | identical, every digit |

That is the policy's own claim — "at one rank this policy is that policy, bit
for bit" — measured at the harness level rather than at the seam.

**Two ranks divide.** Under `mpiexec -n 2`, `OCTOPUS_RANKS=2`, two threads per
rank: both harnesses exit 0, both ranks report, one artifact is written, and
the two ranks' rms differ as two shards of one beam should.

## The pin

`test/runtests.jl`, "The developer harnesses run divided under an MPI
launcher": both harnesses launched at `-n 2` with `OCTOPUS_USE_MPI=1`,
`OCTOPUS_RANKS=2` and their own result directory. It is the only place the
branch executes — the example-runner testset runs these files at their
defaults, which is the switch off.

`OCTOPUS_RANKS=2` is what makes the pin non-vacuous, and it is also the whole
assertion. The policy rejects a communicator whose size differs from an
explicit request, so a child that reached exit 0 had a communicator of two —
which means the extension loaded (without it the process is a communicator of
one and the run throws) and the run was divided. A `ranks=auto` child could not
say that. The pin adds one more durable check, that rank 0 wrote exactly one
artifact into a directory of its own.

What the pin deliberately does NOT assert is the `mpi_rank = r of P` and
shard-labelled rms lines this branch prints. Those arrive through the
launcher's merged stdout, which drops bytes under load — measured the same week
over twenty child runs, three corrupted, which is why the seam check moved its
receipts to per-rank files
([`docs/experiences.md`](../experiences.md), "A launcher's merged stdout is not
a data channel, and a pin built on it lies"). A pin on those strings would
flake about one gate in ten and would prove nothing exit 0 does not.
