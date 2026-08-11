# Targeted Neighbour Audit — the observer/luminosity GPU campaign

Range audited: `4ed84e4` … `6203cf0` (eleven commits, one day: weak-strong
CUDA buffer reuse and device luminosity reduction, the validation-script
repair, `LuminosityObserver` capacity, and the fused → chunked → Val-powers
moment kernels). Measurements in
[`weak_strong_cuda_luminosity_2026_08_11.md`](weak_strong_cuda_luminosity_2026_08_11.md).

## Campaign-wide property, re-run at final HEAD

The owner's constraint was byte-identical physics. The bitwise A/B pin
(references captured at pre-campaign `4ed84e4`; 100k particles, 10 turns,
thin/gaussian × masked/unmasked, RTX 4500 Ada) re-run against `6203cf0`:

| case | coordinates | luminosity |
|---|---|---|
| thin unmasked | bit-identical | bit-identical |
| thin masked | bit-identical | 1.5e-16 rel |
| gaussian unmasked | bit-identical | 1.8e-16 rel |
| gaussian masked+angles | bit-identical | 2.1e-16 rel |

The luminosity deltas are exactly the ones commit `6304601` introduced and
the owner accepted (device reduction order, ≤1 ulp); the five commits that
followed moved **nothing** further. The moment-row changes are
tolerance-pinned against the CPU fold instead, since bitwise cross-backend
moment equality never existed.

## The campaign's property walked to the neighbours it did not change

The campaign's load-bearing property: *a per-turn diagnostic must not copy
per-particle arrays to the host, and only scalars/partials cross PCIe.*
Every per-turn observer/diagnostic surface was checked:

| surface | verdict |
|---|---|
| `MomentObserver` CUDA row | fused kernels (this campaign) |
| `BPMObserver` centroid | device reductions since U7-5, unchanged |
| weak-strong luminosity | device reduction (this campaign) |
| strong-strong PIC luminosity | scalar `Array(x)[1]` + per-block partials only |
| spectral CUDA | scalar drop counter only |
| gaussian-PIC CUDA moments | small (nstats × ncols) matrix only |
| `CoordinateSnapshotObserver` | full copy IS its purpose — exempt by design |
| `BeamMomentObserver` / `JLD2BeamMomentObserver` | **N1 — property violated, ledgered** |

Also re-verified: both weak-strong kernels still assign `lum[index]` for
every index (the precondition the uninitialized workspace buffer documents),
and the deleted `_cuda_compute_moment!` / `_cuda_moment_row_per_moment!`
have zero remaining callers — the only textual survivors are dated history
prose, which describes the commits it audited.

## Findings

**N1 — the legacy moment observers still host-copy the whole beam.
Ledgered.** `BeamMomentObserver` and `JLD2BeamMomentObserver` call
`beam_statistics(rep; diagonal_fourth=true)` per observed turn, and its
first line is `_host_coordinate_arrays(rep)` — 48 MB D2H at 1M particles
plus single-threaded host covariance, the exact class U7-5 fixed in the BPM
and this campaign fixed in `MomentObserver`. Exposure is low: neither
appears in any example, harness, or validation; `MomentObserver` is the
documented choice. Priced: `beam_statistics` means + 6×6 covariance +
diagonal fourths are expressible as fused-kernel power rows (27 + 6 = 33 →
two chunks), so a device path could reuse this campaign's machinery nearly
verbatim — or the pair gets documented as legacy/CPU-appropriate. Todo row
added.

*N1 closure, same day (owner decision):* removed rather than fixed. Both
observers, their writers, schemas, exports, metadata probes, and their suite
pins (U7-2, U7-3, U7-8 — lessons preserved in the dated records) are gone in
the pre-release window; the JLD2 reader branch stays for archived files, and
the U7-10 registry test re-vehicled onto `MomentObserver`. One public moment
observer remains, which is the derive-from-one-source rule applied to output
paths.

*Neighbour audit of the removal itself* (the campaign standard applied to
its own closure): an orphan sweep over all 45 private names remaining in
`BeamObservers.jl` (with `grep -F`, per the 2026-08-10 N2 lesson about `!`
and `\b`) found zero orphaned helpers; the reverse-reference sweep is clean
(the survivors are the reader docstring's historical format string and dated
records); both reader branches were exercised (the HDF5 branch by the
retained U7-4 suite pin, the JLD2 branch against a synthesized
legacy-format file); the coverage tree guard and configuration contracts
re-ran green. **One finding, fixed here (R1):** the removal's own closure
texts claimed "the JLD2/binary READER branches stay" — but the binary
`.bin` format never had an in-tree reader; `MomentOutputFile` branches only
HDF5/JLD2, and the deleted U6-2 test read `.bin` by hand. Nothing readable
was lost, but the claim promised recovery machinery that does not exist —
the verdict-easier-to-misread shape again, this time in an audit record.
Corrected, with the `.bin` layout documented for archival recovery:
`Int32` row count, `Int32` format-string length, CSV column names, then
`Float64` rows (`_initialize_moment_file!` before `3a65c7e`).

**N2 — `BPMObserver` in path mode opens its file every observed turn.
Ledgered.** `BPMObserver.jl:257` is the same open/append/close-per-turn
shape the `.lum` observer had (2.3 ms/turn on the production cluster FS).
Exposure: only when `path=` is set, and BPM studies typically observe many
positions — which multiplies the cost, hundreds of opens per turn on a
cluster FS. Not fixed here because BPM replay REWRITES the file from object
memory (the U7-10/N3 registration model), so capacity buffering must
compose with a different replay mechanism than the `.lum` row-trim. The
`LuminosityObserver` capacity implementation is the worked recipe. Todo row
added.

**N3 — note, no action: second-writer warnings can lag by up to
`capacity` turns.** With buffering, a `LuminosityObserver` registers its
path at first FLUSH rather than first observe, so the two-writers-one-path
warning fires late by at most one buffer. The warning still fires and the
file-safety semantics are unchanged.

**Process lesson, recorded because it nearly bit:** the background gate
wrapper `julia ... Pkg.test ...; tail -3 log` reports the TAIL's exit code,
so a failed gate arrived labeled "exit 0" and was nearly read as green —
the same verdict-easier-to-misread-than-read shape as the 2026-08-10 N1.
The failure was caught by grepping the log before pushing; later gates
print an explicit `GATE_GREEN` sentinel only when `Pkg.test` itself
returns. Worth keeping in the wrapper.

**Verified clean, no action:** the U14-4 reference-pair invariant's blast
radius (the remaining `beta0=0.99, gamma0=100.0` occurrences are the
invariant's own rejection pins in `test/runtests.jl` and the repaired
contract fixture comment); `docs/current_runtime.md` and the registry
snapshot carry no claims about the changed implementations; the Core.Box
tripwire is clean repo-wide at HEAD — and it caught a real box this
campaign introduced (`6203cf0`), which is the gate demonstrating the lesson
mid-campaign; `reduction_scratch` has no stale field documentation; the
strong-strong task-level `.lum` stream and `CUDAPICLaunchConfig` surfaces
were not reachable from any of the campaign's edits.
