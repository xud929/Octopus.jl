# The MPI Environment Traps, Resolved by Test — 2026-09-04

Phase 0 recorded two environment traps and said Phase 1 would "decide with a
test, not an argument"
([`multi_process_phase0_2026_08_19.md`](multi_process_phase0_2026_08_19.md),
"The two environment traps"). This is that test, and the decision it
supports. It also corrects one of the two traps: it is narrower than the
record states. Corrections live beside originals; the Phase 0 record is
untouched.

## What was measured

Four probes on this box (128-thread node, Julia 1.12.4), then the extension
itself.

1. **Both load orders coexist.** Octopus first then `MPI`, and `MPI` first
   then Octopus, both load, write and read an HDF5 file, and complete an
   `Allreduce`. In both orders `libmpi.so` comes from the MPICH_jll artifact
   and `libhdf5.so` from the serial HDF5_jll artifact the tracked Manifest
   installs. HDF5 reads still work after `MPI.Finalize()`.
2. **Trap 1 is loud and immediate.** With an environment carrying
   `MPIPreferences` ahead of Octopus in the load path, HDF5 resolves to an
   MPI variant whose artifact is not installed and fails to precompile:
   `Artifact "HDF5" was not found`, in about ten seconds, before anything
   runs. A configuration mistake that fails at precompile is not a hazard; it
   is a message.
3. **MPICH_jll works under its own launcher.** Octopus loaded first, then
   `MPI`, at one and two ranks under MPICH's `mpiexec`: `MPIPreferences.binary
   == "MPICH_jll"`, per-rank HDF5 round trip correct, `Allreduce` correct.
4. **A system MPI works, with two preferences.** A scratch environment
   pinning `MPIPreferences` to the system Open MPI *and* HDF5 to the matching
   system library (`/usr/lib64/libhdf5.so.200`) runs at one and two ranks
   under `prterun`, with `binary == "system"`.

Then the real thing: `OctopusMPIExt` precompiles and runs the whole collective
seam at 1, 2 and 4 ranks under MPICH_jll's `mpiexec`, with Octopus's HDF5
unpinned, and a one-rank MPI run reproduces a single-process
`CPUThreadsExecutionPolicy` run coordinate for coordinate.

## Correction to trap 2

Phase 0 recorded the second trap as a **load-order lock**: "HDF5.jl itself
depends on MPIPreferences, so loading Octopus first loads MPIPreferences with
its MPICH_jll default — after which no `use_system_binary()` preference is
ever read". Probe 4 contradicts the general form: with the preferences
present in an environment that is on the load path *at process start*,
Octopus loaded first and MPI.jl still ran the system Open MPI. What is true
is narrower — Julia reads a package's preferences from load-path entries
whose `Project.toml` names that package, so preferences pushed onto
`LOAD_PATH` *after* the process has started (which is what the Phase 0
prototype did) can never apply. The trap is real; it is a property of when
the environment is on the load path, not of which package loads first.

## Decision

**MPICH_jll, by default, with no configuration.** The HDF5_jll the Manifest
installs is already an MPI-variant build linked against MPICH_jll's `libmpi`,
so `MPI` on MPICH_jll introduces no second MPI runtime into the process, and
it needs no per-machine file. A system MPI stays available as an opt-in for a
machine whose fabric requires it, and costs two preferences —
`MPIPreferences` for the runtime and an HDF5 pin to a matching library — both
of which fail loudly if only one is set.

*(Owner decision to confirm. Nothing in the code depends on which runtime is
chosen: the seam calls MPI.jl, and MPI.jl calls whichever `libmpi` its
preferences name.)*

## What this leaves open

The tracked `Manifest.toml` could not be re-resolved on this box: an explicit
`CUDA_Runtime_jll` pin (0.23.0) conflicts with the `CUDA_Driver_jll` 13.3.0
requirement, so `Pkg.resolve()` fails before it considers MPI at all. This
predates the multi-process work and is why `Pkg.test` re-resolves into a
temporary environment on every run. The Manifest is therefore left untouched
by step 2, and `MPI` reaches the test environment through `[targets] test`,
which is where the multi-process section's child processes need it. Tracked
in `docs/todo.md`.
