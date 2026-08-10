# Targeted Neighbour Audit — the whole CPU-threading campaign

Second pass, covering the campaign end to end.
[`neighbour_audit_2026_08_09.md`](neighbour_audit_2026_08_09.md) audited fixes
1–4 and is not repeated here; this one covers fixes 5–10 and the
test/benchmark infrastructure, and re-runs the campaign-wide properties on
every sibling.

Range audited: `64169ca` … `b6b38d7`. Measurements in
[`cpu_threading_2026_08_09.md`](cpu_threading_2026_08_09.md).

## The load-bearing property, verified structurally

Fixes 8 and 10 alias a slice as its own kick target — slice `i` is kicked in
place, and only slice `j` is copied — which rests entirely on **no interaction
writing its source**. The digests agreeing is evidence, but only for the
configurations measured, so the property was checked in the code rather than
inferred from them:

| surface | result |
|---|---|
| `_pic_interaction!` | no write to `source.*` |
| `_pic_interaction_node!` | no write to `source.*` |
| `_gpic_interaction!` | no write to `source.*` |
| whole of `pic_cpu.jl` + `gaussian_pic.jl` | no `source.*[i] =` anywhere |
| deposit family (`_pic_deposit_*_range!`, `_pic_deposit_*_serial!`) | write `charge` only |
| `_gpic_solve_drifted_field!`, `…_coupled!`, `_gpic_source_moments` | no source writes |

This matters beyond the default path: `:node` and `:quadratic` route through
different interaction functions, and a source write in either would have made
those modes silently wrong while `:slice_pair` stayed correct.

## Campaign-wide property re-run on every solver

All four coordinate digests at HEAD against the pre-campaign `d0fb3f2`:

| solver | `d0fb3f2` | at HEAD |
|---|---|---|
| PIC | `0x4625d8c583a1efa1` | same |
| GaussianPIC | `0x58fc69d46333dfe0` | same |
| Spectral | `0x00c98cd00a439897` | same |
| soft-Gaussian | `0x193c817f4b56ca7d` | same |

These now come from the nightly benchmark's own `digest` column, so the check
is reproducible from a committed artifact rather than a one-off measurement.

## Blast radius of the shared-surface changes

The campaign changed three surfaces outside the two solvers it optimized:
`_run_logical_workers` (exception unwrapping), `ExecutionAudit` (a lock), and
`_PICCPUWorkspace` (two new fields). Each was walked to its other users:

- **CUDA constructs neither `_PICSlicePairGreenCache` nor `_PICCPUWorkspace`**
  and calls `_run_logical_workers` nowhere, so the struct and exception changes
  cannot reach it. (The GPU paths were untouched by owner constraint; this
  checks that they were not reached *indirectly*.)
- **`spectral.jl` and `gaussian.jl` use neither the PIC workspace nor its
  pool**, so the added fields cannot affect them — confirmed by their digests
  above.
- `_record_execution!` IS reached from CUDA (`_active_cuda_launch`), and now
  takes a lock. Behaviour is unchanged when no audit is active, which is every
  production run; the gate exercises it with CUDA active.

## Findings

**N1 — the benchmark runner reported success on a total failure. Fixed.**
`nightly_benchmark.sh` printed `rows appended to …` unconditionally, so a run
in which every solver failed — and one with no history file, where nothing
could be written — still produced a success-shaped stdout line. The exit code
was correct and stderr carried the failures, but a job whose stdout reads like
success on a total failure is the U21-1/U21-2 lesson in different clothes: the
verdict must not be easier to misread than to read. It now counts outcomes and
says which of them happened. Found by *exercising* the failure path with a bad
solver name, not by reading it.

**N2 — the audit's own orphan sweep was broken, and reported 13 false
positives.** The first pass matched `\b$name\b`; for every helper ending in `!`
the trailing `\b` can never match, since `!` and the following `(` are both
non-word characters. It reported `_pic_copy_slice!`, `_pic_apply_kick_range!`
and eleven others as having zero call sites. Re-run with `grep -F`: no orphans
anywhere. Worth recording because a sweep that flags everything is as useless
as one that flags nothing, and this one would have sent the next reader
deleting live code.

**Verified clean, no action**: no orphaned helper from any of the ten fixes
(each has at least its one call site); no `scratch1` remnant after the
single-copy change removed it; the Float32 variant takes the fast
`_pic_virtual_buffers` path (workspace scalar and buffers both `Float32`, so
the type-mismatch fallback is a genuine safety net, not a hot path) with
luminosity agreeing with `Float64` to ~3e-7.

## Ledgered, not fixed

**Spectral still has the per-pair gather/copy/scatter** the campaign removed
from PIC and gpic (`spectral.jl:1152-1163`), plus per-pair field-array
allocations, and allocates **9.83 GiB/collide** with 27–30% of its wall in GC.
This is not a defect and not a regression — the campaign scoped to the two grid
solvers, which were 8–13x slower — but it is the same shape, and the fix is now
a worked precedent twice over. Priced: spectral is 4.88 s/collide against PIC's
2.99, so it is no longer the bottleneck; do it when spectral matters, not
before.

**Coverage boundary of the new performance guard**: the allocation test
exercises `:slice_pair` with linear interpolation. `:node` and `:quadratic`
allocate their meshes and third field plane once per workspace rather than per
pair, so the property should hold there too — but it is not asserted, and
saying so is better than implying the guard covers every mode.
