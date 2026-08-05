# U4 report — src/tasks/strongstrong/interface.jl (commit 6a3f39a)

## Coverage

Read every line of `/cfs/ad/dxu/Library/Julia/Octopus/src/tasks/strongstrong/interface.jl`
(2,310 lines) at commit 6a3f39a, including an independent read of the full
6a3f39a diff (interface.jl +71/-3 and the new testset in test/runtests.jl).
Cross-file protocol verification: `_task_execution_window`
(src/tasks/Tasks.jl:465), the MomentObserver append path
(src/tasks/BeamObservers.jl:515-1015, commit 80cadbf),
`_strong_strong_luminosity_evaluated` methods for GaussianPIC/Spectral
(gaussian_pic.jl:168, spectral.jl:263-277), `runtime_cache` /
`cache_stats` / `_ACTIVE_PIC_LUMINOSITY_PAIR_SINK` consumers, and knob-epoch
gating in Tasks.jl:529. Probes run CPU-only from the repo root in one Julia
session (`u4_runner.jl`); all outputs confined to scratchpad/U4/.

## Leads

### U4-1 — interface.jl:1717-1722, 1854-1855, 1991-1992 — luminosity_append continuation state does NOT live in the file; a fresh task silently truncates all prior rows — HIGH

Violated invariant: the new docstring (lines 1717-1722) and the
`_prepare_strong_strong_luminosity_file!` docstring (1966-1969) promise the
file "is CONTINUED across `execute!` calls, tasks sharing the path, and
process restarts"; the commit message says "Continuation state lives in the
file, so a second task sharing the path and a process restart both pick up
where it ends."

Reality: `execute!` derives `first_turn` from the in-memory
`task.next_turn[]` Ref (line 1854-1855; initialized to 0 at line 1821), and
the prepare step drops every row with `turn >= first_turn` (1991-1992).
Nothing is ever read *from the file* to position the window. So a second
task sharing the path, or a process restart reconstructing the task, that
does not pass an explicit `start_turn` gets `first_turn = 0` and silently
truncates every prior row — the exact loss `luminosity_append=true` exists to
prevent. Even `turns=0` (a no-op run) wipes the file. No warning, no error.

Measured (probe): task A writes turns [0,1,2] with append=true; fresh task B,
same path, `turns=2`, no `start_turn` → file holds turns [0,1] (3 rows
destroyed; docstring-promised [0,1,2,3,4]). A 10-row file + fresh task +
`turns=0` → 0 rows left.

The new testset (runtests.jl:3273-3324) never exercises a second task or a
restart without `start_turn`; the sibling MomentObserver test (3356-3359)
passes `start_turn=6` explicitly for its "restart" case. MomentObserver has
the identical trap (`_moment_append_continue!` at BeamObservers.jl:1007-1011:
`searchsortedfirst(turn_col, first_turn) - 1` → kept=0 when first_turn=0), so
the two protocols *agree* and compose — but both docstrings overpromise
("process restarts ... produce one file with continuous absolute turns",
BeamObservers.jl:526-531). At minimum this is docstring↔code drift; as
implemented it is a silent-data-loss footgun under the documented workflow.

Repro: scratchpad/U4/u4_1_restart_truncation.jl

### U4-2 — interface.jl:1986, 1993-1998 — append-mode prepare rewrites the whole file non-atomically on every execute!; a crash during prepare loses the entire history — MEDIUM

Violated invariant: a feature whose purpose is surviving process restarts
must not have a window in which a restart-worthy event (kill, OOM, power)
destroys the whole file. In append mode, prepare does `readlines(path)` then
`open(path, "w")` and rewrites header + kept rows. Between the truncating
open and the completed rewrite, the only copy of the history is process
memory; a hard kill there leaves a header-only or partial file. No
write-to-temp + atomic rename. Note the rewrite (and thus the window and the
O(file-size) read+write) happens on *every* append-mode `execute!`, even the
pure-continuation case where `kept` is all rows and nothing needed dropping.
The sibling MomentObserver protocol has no such full-rewrite window: it
shrinks the table in place via `HDF5.set_extent_dims` in "r+"
(BeamObservers.jl:1012-1014). Code-reading lead; crash injection is not
probeable within the probe budget.

### U4-3 — interface.jl:1991-1992, 2053 — torn last line from a hard kill survives the kept-filter as a duplicate turn label — LOW

Violated invariant: prepare's own docstring (1973-1974): "a file carrying two
rows for one turn is corrupt for every reader"; commit promise (c) that
retries cannot duplicate turn labels. The turn is printed first in each row
(line 2053), so a killed process flushing mid-row can leave a torn fragment
whose first field is a *prefix* of the real turn ("1" of "12"). On the
correct retry (`start_turn=12`), `parse(Int, first(split(line)))` parses the
fragment as turn 1 < 12, keeps it, and the file ends with two rows labelled
turn 1 plus a wrong-column-count row. Measured (probe): 14 rows, 2 rows with
turn field "1", 1 row with 1 column instead of 2. A torn fragment that
parses as a float ("1.5") instead makes prepare throw a raw
`ArgumentError` from `parse` with no path-context message. Only reachable
via hard kill mid-flush (exception-path failures flush whole lines because
the `open do` block closes/flushes); hence LOW.

Repro: scratchpad/U4/u4_3_torn_line_duplicate.jl

### U4-4 — interface.jl:1885-1888 vs 1901/1987-1990 — the .lum header guard fires after prepare_observers! has already truncated appendable sibling files; an aborted execute! mutates the moment table having tracked nothing — LOW

Violated invariant: an `execute!` refused before any tracking should leave
outputs unchanged (the commit sells the two append protocols as companions
producing "one luminosity file and one moments file, both contiguous").
Ordering: `prepare_observers!` (1885-1888, outside the try) truncates an
append-mode MomentObserver table to rows < first_turn; the .lum header guard
(1987-1990, inside the try) then throws. Measured (probe): 6 turns recorded
in both files; corrupt the .lum header; `execute!(start_turn=3, turns=3)`
aborts with ArgumentError; moment table is now [0,1,2] (rows 3..5 gone) while
the .lum still holds rows 0..5. The rows are recoverable only by re-running
the same window with correctly-positioned beams.

Repro: scratchpad/U4/u4_4_sibling_truncated_before_header_guard.jl

## Sound — invariants verified and how

- Append scenario (a), no existing file / empty file: prepare writes the
  header once (1980-1985); probe 1 phase 1 shows header + rows 0..2, and the
  6a3f39a testset pins single-header and contiguity across a beam swap.
- Scenario (b), mismatched collision layout: header guard (1987-1990)
  refuses with ArgumentError; reproduced in probe 3 (and pinned by the
  testset). Layouts matching by label but differing in solver/schedule are
  accepted by design — the header carries only labels, and the file is
  documented to contain only evaluated turns, so gaps are legal.
- Scenario (c), exception-path crashed execute! + retry: `task.next_turn[]`
  is assigned only after the body returns (1863), so a failed call replays
  the same window and prepare drops the partial rows — idempotent for
  exception failures (hard-kill residue is U4-3).
- Scenario (e): turn labels are absolute (`ctx.turn` = first_turn + offset,
  2025-2027, 2053), matching `_task_execution_window` (Tasks.jl:465-496,
  checked: overflow-checked, turns>=0, start_turn>=0).
- Protocol agreement with MomentObserver(append=true): both drop rows at or
  beyond the incoming window's first_turn and both take first_turn from the
  task window — they compose (same trap, U4-1, but no drift *between* them).
  Replace-mode default pinned by the testset (turns [3,4,5] after two
  3-turn runs).
- luminosity_append consumers: read at 1980 (prepare) and in
  configuration_report (1771-1778, `:inactive_dependency` when path is
  nothing); constructor stores it (1817). Not a stored-and-never-read option.
- Config-to-consumer sweep: `cache_stats` → pic_cpu.jl:1141/pic_cuda.jl:602;
  `pic_timing`/`pic_timing_detail`/`nvtx`/`memory_log_every` → 2130-2165 and
  PIC files; `runtime_cache` → pic_cpu.jl:28-29 etc. and Contracts.jl:1059;
  `_ACTIVE_PIC_LUMINOSITY_PAIR_SINK` → pic_cpu.jl:114, gaussian_pic.jl:811,
  pic_cuda.jl:3647, Contracts.jl:786. No accepted-but-never-read option found
  in this file's new or old surface.
- Luminosity-schedule dispatch is complete: `_strong_strong_luminosity_evaluated`
  has methods for PIC (2127), GaussianPIC (gaussian_pic.jl:168), Spectral
  (spectral.jl:277); Gaussian deliberately lacks a schedule (docstring 57-60).
- Knob-epoch recompilation: `_strong_strong_runtime_blocks` (2208-2226) gates
  on `knob_epoch()`/`_spec_epoch()` with the same predicate as Tasks.jl:529
  and empties the matching plan cache on rebuild; no other task family found
  lacking the gate.
- Schedule edge cases: `all(luminosity_evaluated)` guarded by
  `!isempty(luminosities)` (2052); empty final block from
  `_split_strong_strong_line` is a no-op (2192). Turn-0 memory-log cadence
  (2153) is intentional-looking and pre-existing.
- No spawned/async closures in this file; the `ScopedValues.with` and
  `open do` closures capture only single-assignment locals (no Core.Box risk;
  `ctx` reassignment at 2027 is a plain loop-local of the function itself).

## Observations (pre-existing, likely covered by earlier parts; not counted as leads)

- interface.jl:2052: with multiple IPs and mixed schedules, one skipped IP
  drops the whole row including sibling IPs' evaluated luminosity; the
  docstring (1087-1094) is ambiguous for the mixed case.
- interface.jl:2281 `_collision_solver` compares solver objects by identity
  (`!==`): two structurally identical solvers on the two lines' markers are
  refused. Documented in the error text; noted for completeness.
