#!/bin/bash
# Nightly CPU strong-strong benchmark, appending to a TRACKED history file.
#
# Why this exists. The suite's performance guard
# ("CPU strong-strong collide allocation does not scale with the pair count")
# asserts ALLOCATION, because a wall-clock bound inside `runtests.jl` would
# abort the whole gate on one flake -- the suite stops at its first failure, and
# that would take the CUDA half with it. That guard therefore catches the
# regression class the 2026-08-09 threading campaign was about (work that scales
# with slice PAIRS instead of slices) and does NOT catch a kernel that simply
# gets slower without allocating. This job is the other half: real timings, on
# real hardware, recorded over time, where a slow drift is visible as a trend
# rather than as a threshold nobody dared set.
#
# Output: one appended row per solver per run in
# `docs/history/cpu_benchmark_history.tsv` -- inside the repository and TRACKED,
# unlike `result/` (gitignored) and unlike `test/nightly_suite.sh`'s
# `~/.octopus_nightly/status.tsv`. A benchmark history is exactly the kind of
# provenance AGENTS.md says belongs in the repository, and a trend is only
# readable if the rows survive the machine that produced them.
#
# It does NOT commit. A cron job that commits to `main` is an unattended write
# to shared history; the operator (or the next agent session) commits the rows
# after looking at them. The script says so on exit.
#
# ---------------------------------------------------------------------------
# NOT INSTALLED ON THE 128-THREAD BOX, DELIBERATELY.
#
# `test/nightly_suite.sh` was installed there on 2026-08-05 and REMOVED on
# 2026-08-07 at the system manager's direction: scheduled long-running jobs are
# not permitted on that machine. That directive is about the schedule, not about
# that particular script, so it binds this one too. This script therefore ships
# inert, exactly as the suite gate does, and is opt-in per machine.
#
# Install (per machine, user crontab, an off-hour and off-:00 minute so it does
# not collide with anything else that runs on the hour):
#
#     23 3 * * * /path/to/Octopus/profiling/nightly_benchmark.sh
#
# Run it by hand the same way -- it takes ~10 minutes at the production point.
# ---------------------------------------------------------------------------
#
# Conventions borrowed from `test/nightly_suite.sh`, and for its reasons:
#   * the exit code comes from `$?` immediately after the command, never from
#     the log -- the benchmarked program writes there too (U21-1/U21-2);
#   * every exit path records something, so a wedged or misconfigured job is
#     distinguishable from one that ran and passed (U21-3/U21-4);
#   * the lock is claimed by an atomic rename, so two runs that both see it as
#     stale cannot both proceed (U21-6);
#   * the stamp carries a time, not just a date, because two runs can land on
#     one day (U21-7).

set -u

REPO="$(cd "$(dirname "$0")/.." && pwd)"
JULIA="${OCTOPUS_BENCH_JULIA:-julia}"
THREADS="${OCTOPUS_BENCH_THREADS:-16}"
SOLVERS="${OCTOPUS_BENCH_SOLVERS:-pic gaussian_pic spectral gaussian}"
N_ELE="${OCTOPUS_BENCH_N_ELE:-2560000}"
N_PRO="${OCTOPUS_BENCH_N_PRO:-1024000}"
REPEATS="${OCTOPUS_BENCH_REPEATS:-3}"
SLICES="${OCTOPUS_BENCH_SLICES:-15}"
GRID="${OCTOPUS_BENCH_GRID:-128}"
HISTORY="${OCTOPUS_BENCH_HISTORY:-$REPO/docs/history/cpu_benchmark_history.tsv}"
OUTDIR="${OCTOPUS_BENCH_LOGDIR:-$HOME/.octopus_benchmark}"
STAMP="$(date +%Y%m%d_%H%M%S)"
LOG="$OUTDIR/$STAMP.log"
LOCK="$OUTDIR/lock"

# Resolved with -C rather than after `cd`, so the early-exit paths still name
# the tree they refer to.
COMMIT="$(git -C "$REPO" describe --always --dirty 2>/dev/null || echo unknown)"

note() { printf '%s\n' "$*" >&2; }

# A solver that crashes writes no row, and "no row" is the record of several
# different failure modes at once (U21-3). This writes one anyway, with the
# shape DERIVED from the file's own header rather than hand-copied here -- the
# header lives in `benchmark_collide_cpu.jl`, and a second copy of it in this
# script would be exactly the kind of duplicated knowledge that silently falls
# out of step (AGENTS.md: derive from the one authoritative source).
emit_failure_row() {    # solver
    # The one case with nothing to derive from is a history file that does not
    # exist yet -- a first run in which every solver failed. That leaves no row,
    # so it has to be loud instead; stderr and a nonzero exit are the record.
    if [ ! -f "$HISTORY" ]; then
        note "octopus benchmark: no history file yet, so $1's failure leaves no row"
        return 0
    fi
    head -1 "$HISTORY" | awk -F'\t' \
        -v s="$STAMP" -v c="$COMMIT" -v h="$(hostname)" -v sol="$1" \
        -v thr="$THREADS" -v ne="$N_ELE" -v np="$N_PRO" -v sl="$SLICES" -v gr="$GRID" '
        {
            for (i = 1; i <= NF; i++) {
                v = "FAILED"
                if      ($i == "datetime")      v = s
                else if ($i == "commit")        v = c
                else if ($i == "host")          v = h
                else if ($i == "tag")           v = "nightly"
                else if ($i == "solver")        v = sol
                else if ($i == "n_ele")         v = ne
                else if ($i == "n_pro")         v = np
                else if ($i == "slices")        v = sl
                else if ($i == "grid")          v = gr
                else if ($i == "julia_threads") v = thr
                printf "%s%s", v, (i < NF ? "\t" : "\n")
            }
        }' >> "$HISTORY"
}

if ! mkdir -p "$OUTDIR" 2>/dev/null; then
    note "octopus benchmark: cannot create $OUTDIR -- refusing to run blind"
    exit 1
fi

if ! mkdir "$LOCK" 2>/dev/null; then
    if [ -n "$(find "$OUTDIR" -maxdepth 1 -name lock -mmin +1440)" ]; then
        CLAIM="$LOCK.stale.$$"
        if mv "$LOCK" "$CLAIM" 2>/dev/null; then
            rmdir "$CLAIM" 2>/dev/null
            mkdir "$LOCK" 2>/dev/null || { note "octopus benchmark: LOCKED"; exit 0; }
        else
            note "octopus benchmark: LOCKED"; exit 0
        fi
    else
        note "octopus benchmark: LOCKED"; exit 0
    fi
fi
trap 'rmdir "$LOCK" 2>/dev/null' EXIT

cd "$REPO" || { note "octopus benchmark: cannot enter $REPO"; exit 1; }

echo "== octopus cpu benchmark  $STAMP  commit $COMMIT  threads $THREADS" > "$LOG"

# `JULIA_THREAD_SLEEP_THRESHOLD=0` so the recorded utilisation means what it
# says: idle Julia threads otherwise spin in `poptask` and that spinning would
# be counted as work. It changes no results.
FAILED=0
for solver in $SOLVERS; do
    echo "-- $solver" >> "$LOG"
    OCTOPUS_BENCH_SOLVER="$solver" \
    OCTOPUS_BENCH_N_ELE="$N_ELE" \
    OCTOPUS_BENCH_N_PRO="$N_PRO" \
    OCTOPUS_BENCH_REPEATS="$REPEATS" \
    OCTOPUS_BENCH_SLICES="$SLICES" \
    OCTOPUS_BENCH_GRID="$GRID" \
    OCTOPUS_BENCH_TAG=nightly \
    OCTOPUS_BENCH_TSV="$HISTORY" \
    OCTOPUS_BENCH_STAMP="$STAMP" \
    OCTOPUS_BENCH_COMMIT="$COMMIT" \
    JULIA_THREAD_SLEEP_THRESHOLD=0 \
        "$JULIA" --startup-file=no --project=. --threads="$THREADS" \
        profiling/benchmark_collide_cpu.jl >> "$LOG" 2>&1
    CODE=$?
    # From $? directly, never scraped back out of $LOG: the benchmark writes
    # there too, and a trailing line without a newline once turned a passing
    # run into a recorded failure (U21-1).
    if [ "$CODE" -ne 0 ]; then
        FAILED=1
        note "octopus benchmark: $solver exited $CODE -- see $LOG"
        emit_failure_row "$solver"
    fi
done

ln -sfn "$LOG" "$OUTDIR/latest.log"
# Keep the last 14, as the suite gate does.
ls -1t "$OUTDIR"/*.log 2>/dev/null | tail -n +15 | xargs -r rm -f

echo "octopus benchmark: rows appended to $HISTORY"
echo "octopus benchmark: NOT committed -- review and commit the new rows yourself"
exit "$FAILED"
