# U53: test/: the MPI seam check and fixture, the turn-modulation probe, the nightly suite script

Tree: `/cfs/ad/dxu/Library/Julia/Octopus` at 24e8683, read-only. Every lead below is a LEAD, not a
finding. Scratch (probe scripts, logs): `result/comprehensive_audit_2026_10_18/probes/U53/`.

## Region

| file | lines | read |
|---|---|---|
| `test/mpi_seam_check.jl` | 1-667 | every line |
| `test/mpi_seam_check_fixture.jl` | 1-616 | every line |
| `test/turn_modulation_probe.jl` | 1-543 | every line |
| `test/nightly_suite.sh` | 1-159 | every line |

Total 1985 lines, all read line by line.

## Provenance

READ (line by line): the four region files in full. READ as consumers/references (not region,
for the hypotheses only): `test/runtests.jl` 23020-23830 (the MPI seam parent: launch, receipt
files, every assertion) and 20995-21195 (the turn-modulation probe parent); `.github/workflows/ci.yml`
in full; `docs/design/testing_lanes.md` sections 1, 3, 4; `docs/design/multi_process_policy.md`
lines 160-172 and 600-612; `docs/current_runtime.md` 814-834; `docs/experiences.md` 1756-1766;
`docs/history/comprehensive_audit_2026_08_05_b_unit_reports/U21_report.md` 67-184 (U21-1..9);
`src/policies/Policies.jl` 626-650 and 755-790 (`_mp_lane_fold!`, `_mp_resolve_shard`) plus the
`_mp_*` definition list; `src/tasks/strongstrong/interface.jl` 2526-2562 (`_solver_divides`,
`_reject_undivided_solver`); the four `*_slice_exchange` receipt sites (`spectral_sliced.jl`
667-687, 1322-1342; `pic_cpu_sliced.jl` 1423-1443, 2094-2114); `src/elements/crab_cavity.jl`
229-244 (the kick kernel) and 44-45/321/373 (the `(1 + d)` rule); `src/tasks/BeamObservers.jl`
825-843 (`BeamSwapAction`); MPI.jl `src/environment.jl` (`Init`, the atexit hook) at
`~/.julia/packages/MPI/pvbg6`.

EXECUTED (all read-only; scripts and logs under `probes/U53/`):

1. `probeA` — `die_in_collective.jl` under `mpiexec -n 2` (MPICH_jll launcher, the project env),
   rank 1 dies while rank 0 waits in `Allreduce`; mode `exit` = `exit(1)` (the seam child's `fail`),
   mode `error` = uncaught `error()` (the TM child's `rethrow`). Log `probeA_exitcodes.log`:
   `mode=exit mpiexec_exit=1 elapsed=3s rank0_left_allreduce=0`;
   `mode=error mpiexec_exit=1 elapsed=4s rank0_left_allreduce=0`.
2. `probeB` — `onerank_direction.jl` under `mpiexec -n 1 ... --threads=2` with
   `MultiProcessExecutionPolicy(threads=1)` and the real fixture: the seam child's four "must RUN at
   one rank" arms with every exception surfaced. Log `probeB.log`:
   `ARM 3c tracking task with BeamSwapAction(identity): THREW MethodError: no method matching length(::TrackingContext)`;
   `ARM 4a equal_count slicing: ran, no exception`; `ARM 4c _reject_undivided_solver(dummy): ran, no exception`;
   `ARM 4b strong-strong task with a line action: THREW ArgumentError: MomentObserver(name="m1") is an artifact view: the task must carry artifact=RunArtifact(...)`;
   `ext loaded: true`, `nranks in scope = 1`.
3. `nightly_stubs.log` — the previous audit's four stub repros (U21-1..4) plus a coverage-drop case
   and a header-migration case, run against a COPY of the current `nightly_suite.sh` in a scratch
   `fake_repo/test/` layout with stub julia binaries and sandbox `HOME`s. Rows measured:
   U21-1 stub (prints `exit=0`, no trailing newline, exits 1): `1 yes FAIL 1`, script exit 1.
   U21-2 stub (no trailing newline, exits 0): `1 yes PASS 0`, script exit 0.
   U21-3 (fresh lock held): `0 unknown LOCKED 0`, script exit 0, row written.
   U21-4 (unwritable HOME): stderr `cannot create ... -- no row can be recorded`, script exit 1.
   coverage drop (3 testsets then 2): second row `2 yes PASS_FEWER 0` with the stderr notice.
   header migration (pre-existing 5-column file holding `151 PASS`, then a 2-testset pass): old
   header `date commit testsets verdict exit` kept, new 6-column row appended, NO coverage-drop
   notice.
   Disclosure: in this batch the copied script's `git -C "$REPO" describe` resolved the
   repository's HEAD (`v0.1.9-630-g24e8683`) because the scratch directory lies inside the working
   tree; that was a read-only `describe`, nothing was written or changed. The later experiments ran
   from `/tmp` (`commit=unknown`).
4. `nightly_stale_lock.log`, `nightly_stale_lock2.log` — the stale-lock reclaim with the original
   run outliving (first) and not outliving (second) the reclaiming run, from `/tmp`. Second log:
   `while runs 1 and 2 both alive, lock present: yes`; `run 1 finished ...; lock present after its
   trap: NO; run 2 alive: yes`; `run 3 exit=0; run 2 still alive during run 3: yes`; three `PASS`
   rows.
5. Read-only measurements on existing records: `~/.octopus_nightly/status.tsv` (4 rows: header +
   three; column counts 5,5,5,6; `awk ... $4==yes` BEST = 0 although a `151 PASS` row exists);
   `~/.octopus_nightly/*.log` (`20260805`: 151 `^Test Summary`, `exit=0`; `20260806`: 151, `exit=143`;
   `20260807`: 0, `exit=137`, 8253 bytes, no `NO CUDA DEVICE`); `crontab -l` has no octopus entry;
   `result/gates/turnmod/full_gate_avx2_canon_gateE.log` (complete, "tests passed", CUDA active):
   351 `^Test Summary` lines; `ls /tmp/octopus_mpi_seam_check*.h5`: five files dated 2026-10-18 11:42.

## Leads

### LEAD U53-1 [Major, confidence high] test/mpi_seam_check.jl:248
Claim: the one-rank direction of both action-refusal arms (3c at lines 248-260, 4b at 385-401) is a check that cannot fail, and it is currently hiding that neither action task runs at one rank at all.
Mechanism: `threw = try ...; false catch err; err isa ArgumentError && occursin("task actions"|"line action", sprint(showerror, err)) end` maps EVERY exception other than the named refusal to `false`; at one rank `expected = Octopus._mp_nranks() > 1` is `false`, so an unrelated crash satisfies `threw == expected` and the child prints `MPI-SSREFUSE spectral_ran=true action=false`, which the parent (`test/runtests.jl`, the `MPI-SSREFUSE` assertions) reads as "runs at one". Measured at one rank under the multi-process policy (probe B): the 3c task throws `MethodError: no method matching length(::TrackingContext)` — `BeamSwapAction(provider)` swaps in `provider(ctx)` (`src/tasks/BeamObservers.jl:836-843`), so `identity` hands the TrackingContext back as the beam; the 4b task throws `ArgumentError: MomentObserver(name="m1") is an artifact view: the task must carry artifact=RunArtifact(...)` because `_mpi_check_ss_task_with_action` (`test/mpi_seam_check_fixture.jl:602-604`) builds `observers=true` lines with no `artifact`. At two and four ranks the refusal fires first and the direction IS verified (the specific message is required); the "and runs at one" half of the child's comment (lines 369-373) and of the parent's has never executed a line action under the policy. The same one-directional shape at lines 309-317 (`:equal_count`) and 532-545 (the undivided-solver tripwire) measured to genuinely run at one rank (probe B arms 4a and 4c), so those two are sound today but share the shape; the fix is to rethrow anything that is not the expected refusal (and to give the action fixtures a valid provider and an artifact).
Repro: `cd /cfs/ad/dxu/Library/Julia/Octopus/result/comprehensive_audit_2026_10_18/probes/U53 && /home/cfsd/dxu/.julia/artifacts/8bd6881e43b97a8d20af0db9dbda166281c02323/bin/mpiexec -n 1 julia --project=/cfs/ad/dxu/Library/Julia/Octopus --startup-file=no --threads=2 onerank_direction.jl 2>&1 | grep '^ARM'` — expect two `THREW` lines (3c `MethodError ... length(::TrackingContext)`, 4b `ArgumentError ... artifact view`) and two `ran, no exception` lines (4a, 4c).

### LEAD U53-2 [Minor, confidence high] test/nightly_suite.sh:89
Claim: the stale-lock reclaim (lines 89-111) leaves the superseded run's `EXIT` trap pointed at `$LOCK`, so when the wedged run finally exits it removes the lock the reclaiming run holds and a third run proceeds concurrently.
Mechanism: `trap 'rmdir "$LOCK" 2>/dev/null' EXIT` (line 111) is unconditional and names the shared path; after `mv "$LOCK" "$CLAIM"; mkdir "$LOCK"` the new directory belongs to the reclaimer, but the old process's trap still `rmdir`s it on exit. Measured (`nightly_stale_lock2.log`): run 1 (8 s) holds the lock, the lock is backdated 3 days, run 2 (20 s) reclaims; when run 1 exits the lock is gone while run 2 is alive, and run 3 then acquires it and runs to a `PASS` row while run 2 is still running (three `PASS` rows where the third should have been `LOCKED`). Low practical frequency (needs a >24 h wedged run that later exits), but it is the same class U21-6 fixed by the atomic rename.
Repro: copy `test/nightly_suite.sh` into `/tmp/x/fake_repo/test/`, use three stub "julia" scripts that `sleep 8`, `sleep 20`, `sleep 2` then print one `Test Summary:` line and exit 0; start run 1 (sleep 8), `touch -d '3 days ago' $HOME/.octopus_nightly/lock`, start run 2 (sleep 20), wait for run 1, start run 3 (sleep 2) — expect `[ -d lock ]` false after run 1 and three rows in `status.tsv` (see `probes/U53/nightly_stale_lock2.log` for the exact sequence).

### LEAD U53-3 [Minor, confidence high] test/nightly_suite.sh:75
Claim: `status.tsv`'s header is written only when the file does not exist (lines 75-76), so the format change that added the `cuda` column and renamed `date` to `datetime` left the existing file with a 5-column header over 6-column rows, and the per-mode `BEST` query (lines 139-142) silently discards every pre-change row — including the only `151 PASS` baseline — because `$4` is the verdict there.
Mechanism: `awk -F'\t' -v c="$CUDA" 'NR>1 && $4==c && $3+0>m ...'` compares the verdict column of old rows against `yes`/`no`; measured on the real `~/.octopus_nightly/status.tsv` (header `date commit testsets verdict exit`, rows of 5,5,6 columns): `BEST` for `cuda=yes` is 0 although row 2 is `151 PASS 0`. The stub case (`nightly_stubs.log`, "header migration") shows a 2-testset pass appended under the old header with no `COVERAGE DROP` notice. The header also misdescribes the rows a human reads with `column -t`, which `docs/current_runtime.md:826-828` recommends.
Repro: `awk -F'\t' -v c=yes 'NR>1 && $4==c && $3+0>m {m=$3+0} END {print m+0}' ~/.octopus_nightly/status.tsv` → `0`; `awk -F'\t' '{print NF}' ~/.octopus_nightly/status.tsv` → `5 5 5 6`.

### LEAD U53-4 [Minor, confidence high] test/nightly_suite.sh:125
Claim: the header's calibration numbers ("the number is 158 with a GPU and 142 without on this suite", lines 125-127) are stale prose of the kind the same comment warns about; and `docs/current_runtime.md:820` still describes the row as "date/commit/testsets/verdict/exit" (no `cuda` field).
Mechanism: the script never reads these numbers (it compares against the best row seen), so nothing keeps them honest; a complete full gate on this machine with CUDA active (`result/gates/turnmod/full_gate_avx2_canon_gateE.log`, ending "Testing Octopus tests passed") has 351 `^Test Summary` lines, the 2026-08-05 nightly log had 151, so the quoted 158 matched no run that this record holds. Class 14 (documentation as claims).
Repro: `grep -c '^Test Summary' /cfs/ad/dxu/Library/Julia/Octopus/result/gates/turnmod/full_gate_avx2_canon_gateE.log` → 351; `grep -c '^Test Summary' ~/.octopus_nightly/20260805_175308.log` → 151; `grep -n 'date/commit/testsets/verdict/exit' docs/current_runtime.md` → line 820.

### LEAD U53-5 [Minor, confidence med] test/nightly_suite.sh:137
Claim: the `cuda` column is inferred from the ABSENCE of a banner string hand-copied from `test/runtests.jl:149` (`NO CUDA DEVICE`), with no tripwire tying the two, so a log truncated before CUDA detection — or a renamed banner — is recorded `cuda=yes`.
Mechanism: `if grep -q 'NO CUDA DEVICE' "$LOG"; then CUDA=no; else CUDA=yes; fi` has no positive evidence branch. The real 2026-08-07 row reads `0 yes FAIL 137` from an 8253-byte log killed before the suite started (no banner either way). The verdict is unaffected (it is `$CODE`), but the mode column feeds the per-mode `BEST` baseline (lines 139-142), so a run classified into the wrong mode either compares against the wrong baseline or seeds it. Class 2 and 11 (a hand-copied string; a recorded mode nothing asserted).
Repro: `grep -c 'NO CUDA DEVICE' ~/.octopus_nightly/20260807_024701.log` → 0 while `tail -1 ~/.octopus_nightly/status.tsv` shows `yes` for that run; `grep -n "NO CUDA DEVICE" test/runtests.jl test/nightly_suite.sh` → the two unlinked copies.

### LEAD U53-6 [Minor, confidence high] test/mpi_seam_check.jl:223
Claim: the child's run artifacts use FIXED names under the shared `tempdir()` (`octopus_mpi_seam_check_3c.h5` at line 223; `octopus_mpi_seam_check.h5`, `_4b.h5`, `_4b_big.h5`, `_4c.h5` from `test/mpi_seam_check_fixture.jl:80,181,255,492`), unlike the per-launch `mktempdir()` the receipt directory gets, so two suites or gate arms on one machine with one `TMPDIR` race on the same five HDF5 files.
Mechanism: rank 0 `rm`s and recreates each file at the start of its step; a second concurrent child (another `Pkg.test`, the second arm of a two-arm gate) deletes or rewrites the file the first is reading for its `MPI-SSLUM`/`MPI-PICLUM`/`MPI-MOM` lines, and the failure would read as a wrong receipt rather than a collision. Evidence that the names are shared across runs: the five files persist in `/tmp` from the 2026-10-18 11:42 gate. A fixed name also means a stale file from a killed run is what `isfile(path) && rm(path)` removes, which is harmless, but nothing distinguishes "mine" from "another run's".
Repro: `ls -la /tmp/octopus_mpi_seam_check*.h5` (five fixed names); `grep -n 'joinpath(tempdir()' test/mpi_seam_check.jl test/mpi_seam_check_fixture.jl` versus `mktempdir()` in the parent's `run_ranks`.

### LEAD U53-7 [Minor, confidence med] test/mpi_seam_check_fixture.jl:494
Claim: `_MPICheckDroppedLogger` (lines 494-510) swallows EVERY log record raised inside the variant collides, not just the dropped-particle count, under a justification ("so the child's stdout stays the lines the parent parses") that the per-rank receipt files made obsolete.
Mechanism: `handle_message` keeps `kwargs[:dropped]` and returns `nothing` for everything else, with `min_enabled_level = Info` and `shouldlog = true`; a `@warn` a divided collide raises (the inactive-option warnings at `src/tasks/strongstrong/interface.jl:2824,2834`, or any new one) is invisible in the child, while the child's stdout is now a file and Julia logs go to stderr anyway. Class 6 (silenced warning), low impact today because the arms are all CPU options.
Repro: `grep -n 'handle_message\|return nothing' test/mpi_seam_check_fixture.jl` and `grep -n '@warn' src/tasks/strongstrong/interface.jl | head`.

### LEAD U53-8 [Minor, confidence high] test/runtests.jl:23503 (out of region; a seam the auditor owns)
Claim: the child's `MPI-PICLAYOUT beam=.. groups=.. out=.. in=..` line (`test/mpi_seam_check.jl:466-470`) carries migration counts that the parent prints but never checks; the parent's comment "and the live members all left" has no assertion behind it.
Mechanism: the parent asserts `startswith(layout[1], "beam=1 groups=$(join(g1, ",")) out=")` and the same for beam 2 — the prefix ends at `out=`, so `migrated_out`/`migrated_in` are free. Hypothesis-3 shape (a claim printed, not checked) on the seam child.
Repro: `grep -n 'MPI-PICLAYOUT' test/runtests.jl` → only the two `startswith(..., "out=")` assertions.

## Clean

- Hypothesis 1 (receipt channel, dropped lines, rank-local vs gathered): compared every emitter
  in the child against its extractor in the parent. Receipts go to `rank_<r>.txt` in a per-launch
  `mktempdir()` (child 38-52, parent `run_ranks`); the parent counts delivered files and asserts
  `got1 == 1, got2 == 2, got4 == 4`. Every tag the parent reads is extracted with an anti-vacuity
  form: `length(tagged(out, tag)) == 1` or `== [..]` (MPI-MOMROWS, MPI-LOSS, MPI-SNAPIDS/LOSSIDS/LOSSSUM,
  MPI-SLICE, MPI-SS*, MPI-SSBIG*, MPI-SSPOISON, MPI-PIC*, MPI-SPECDENY, MPI-PICBIG), `!isempty` plus
  `all(==ref)` (MPI-LUM, MPI-PICVARZ, MPI-SPECVARZ, MPI-SPECVARLUM), `length == P` (MPI-SPECVARWORK,
  MPI-PICVARLUM at two ranks), `variant(...) !== nothing` (MPI-PICVAR, MPI-SPECVAR), `first(...)` on an
  empty generator errors (MPI-MOM), `joined(out) == reference` with `length(reference) > 10_000`
  (MPI-TRACK). A dropped line therefore fails loudly; none passes vacuously. Rank-local vs gathered:
  every rank-0-only line inside a policy scope is guarded by `Octopus._mp_is_root()`, every one
  outside a scope by `child_rank()` (the communicator's rank); the one outside-scope `_mp_is_root()`
  (line 381, the MPI-SPECTASKERR failure path) would write on every rank into per-rank files and the
  parent asserts the tag EMPTY, so the misuse cannot pass anything. Whole-beam fingerprints use
  collectives inside `_with_beam_shards` (`_mpi_check_collide_signature`), the 4a lesson.
- The "exits non-zero so a dying rank takes the launcher down" claim (child header 9-11, TM
  docstring 489-490): measured true (probe A): `mpiexec` returned 1 in 3-4 s in both the `exit(1)`
  and the uncaught-error modes with the peer parked in `Allreduce`; MPI.jl's atexit hook finalizes
  only when `exitcode == 0` (`environment.jl` `Init`, "If we are terminating due to a Julia
  exception, we shouldn't call MPI_Finalize"), so no rank blocks in a collective finalize. The parent
  additionally bounds each launch with a 1800 s watchdog.
- Receipt counting in the fixtures: `:spectral_slice_exchange` and `:pic_slice_exchange` are recorded
  once per collide per rank, at the end of either loop (`spectral_sliced.jl:681,1336`;
  `pic_cpu_sliced.jl:1437,2108`), so the spectral fixture's `exch[1]` and the child's summed PIC form
  (lines 428-434, two turns) agree with their consumers; `length(sched) == 1 || error(...)` is loud
  in both collide-line helpers. `_mp_lane_fold!` is `_mp_allsum_impl!` today (`Policies.jl:628-631`),
  matching the child's expectation; `_mp_resolve_shard` outside a scope returns `(0, local_n)`
  (`Policies.jl:757-759`), which is exactly the no-op the fixture's poisoned-beam comment describes
  and guards with its anti-vacuity `error`.
- Hypothesis 3 (the TM probe's claims are checked): every header claim maps to an asserted field in
  the parent's `assert_verification` — comparison 1 → `c1.bitwise`, `c1.max_abs == 0`,
  `c1.receipt_identical`, `series_on/off`, `nothing_recorded_for_plain`; comparison 2 → `px_all`,
  `px_first == 1`, `pz_all`, `pz_first == 1`, `py_equal`, `receipts == (1,1,0)`, `window_ok`;
  comparison 3 → `series_eq_replay`, `same_as_read`, `nominal_recorded`, `start_turn == [0]`,
  `window_turns == [64]`, `active_nonzero`, `inactive_zero`, `max_dphi/max_d` floors, per-run
  `turns_ok/xyz_const/py_const/dpy_zero`, `px_ulp == 0 && pz_ulp == 0` and `chain == 0` where exact,
  `excess <= 1e-14` on CUDA, `within`, the CPU-reference `series_bitwise`/`rows_bitwise`, and
  `tm_probe_pass(r)`; the two-rank arm's parent asserts `success(proc)`, `delivered == 2`, exactly
  one `TM-PROBE-DONE ... pass=4/4 coverage=true verdict=PASS`, four `TM-PROBE backend=mpi2` lines, no
  `TM-PROBE-FAIL`, eight `TM-PROBE-SHARD` lines with `sum(nlocal) == 1` per label, and re-reads the
  child's artifacts itself (rows and recorded series bitwise against the CPU arm). Only `max_abs`,
  `step_ulp`, `chain` and `px_first` are information in the child's line, and each is asserted or
  implied in the parent. `tm_probe_kick` mirrors `track_particle(::Symplectic6DMap, ::ThinCrabCavity, ...)`
  (`crab_cavity.jl:229-244`) operation for operation (`ikcc = T(i) * kcc`, `θ = ikcc * z0 + phase[i]`,
  `dpx -= sx * s / ikcc`, `dpz -= (sx * x0 + sy * y0) * c`, `px0 + dpx`), and the `(1 + d)` relative
  factor is the documented rule (`crab_cavity.jl:44-45, 321`). The child's exit protocol is sound:
  `nranks != 2` → `TM-PROBE-FAIL` + `error`, any exception → `TM-PROBE-FAIL` + `rethrow`, rank 0
  `exit(1)` on a failed verdict after the final barrier (no pending collective).
- Hypothesis 2 (the nightly's exit code; toggles): `CODE=$?` is taken directly from the julia
  command (line 118), `exit "$CODE"` is the last statement, the `EXIT` trap does not alter the
  status, and no pipe sits between the command and `$?`. The four defects of the previous audit
  measure fixed on the current script (stub rows `FAIL 1`, `PASS 0`, `LOCKED 0`, and a loud exit 1
  with no writable `$OUTDIR`); the coverage tripwire fires (`PASS_FEWER` with the stderr notice).
  The gate line is `.github/workflows/ci.yml`'s verbatim (`julia --project=. --threads=4 -e 'using Pkg;
  Pkg.test(julia_args=["--threads=4"])'`); CI additionally runs `Pkg.instantiate()`, whose absence
  here would fail loudly (non-zero `Pkg.test`), not silently. The script sets no environment toggle
  the suite reads: the suite's only `ENV` reads are `OPENBLAS_CORETYPE` (printed), `GITHUB_ACTIONS`
  (annotation output only) and `OCTOPUS_SKIP_SCRIPT_MODE_TEST`; the thread count is passed where the
  suite consumes it (`julia_args`). The nightly being installed nowhere (no crontab entry; last row
  2026-08-07) is the documented state (`docs/current_runtime.md:832-834`, `docs/experiences.md:1758-1760`),
  not a defect.
- Style only (no lead): `tm_probe_verify`'s docstring (343-344) says non-root ranks "return
  `nothing`" while they return a NamedTuple with `root=false`, which every consumer handles; the
  parent does not assert the `MPI-CHECK` receipt lines at four ranks (`ok4` and `got4 == 4` cover the
  run), a weaker but not vacuous form.

## Unchecked

- The full seam child was not re-run at 1, 2 and 4 ranks here (minutes per launch; the committed
  gate logs cover it). Probe B re-ran only the four one-rank arms, at one rank.
- The TM probe's CUDA arm and the two-rank child were not executed in this unit (the suite's full
  lane runs them); their logic was read, not measured.
- The parent's cross-rank tolerances (`rtol = 1e-12`) and the layout-rule expectations
  (`_mpi_check_pic_partials`, `armloop`) were read for shape only; whether the measured drift still
  sits inside them is the parent unit's question.
- Whether `BeamSwapAction(identity)` would also fail under `CPUThreadsExecutionPolicy` was not run
  separately; by `BeamSwapAction`'s docstring the provider is called with the context regardless of
  policy, so the 3c `MethodError` is policy-independent by construction.
- The nightly script was exercised only through a scratch copy with stub binaries, never against a
  real suite run; the one real-suite measurement is the 351-testset count read from an existing gate
  log.
