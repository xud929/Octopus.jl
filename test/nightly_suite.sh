#!/bin/bash
# Nightly full-suite gate for machines that carry what CI cannot: this
# repository's CI runner has no GPU, so the CUDA half of the suite -- the
# half the pic_cuda.jl correctness argument rests on -- executes only where
# someone runs it. That gap is the repository's dominant recorded failure
# class ("correct check, never executed"; docs/comprehensive_audit.md,
# Measured Lessons 1 and 9), and this script is its standing counterweight:
# the exact CI gate invocation, nightly, on a GPU machine, with an honest
# exit-code record.
#
# Install (per machine, user crontab; an off-hour, off-:00 minute):
#
#     47 2 * * * /path/to/Octopus/test/nightly_suite.sh
#
# Output: $HOME/.octopus_nightly/<date>.log (last 14 kept),
# `latest.log` symlink, and one appended row per run in `status.tsv`:
# date, commit (--dirty marked), testset count, verdict, exit code.
# The verdict is PASS, FAIL, LOCKED (another run held the lock, so this one did
# nothing) or ERROR (the repository could not be entered). LOCKED and ERROR
# exist so that a gate which did not run still leaves a row: "no row" used to be
# the record of four different failure modes at once (U21-3/U21-4).
# Check it with:  column -t ~/.octopus_nightly/status.tsv | tail
#
# The suite's own exit code is the verdict, and it is taken from the shell,
# never from the log. Measured Lesson 9 is about a trailing pipe eating a
# failing status; this script originally answered that by echoing `exit=$?`
# INTO the log and scraping it back with sed -- which is a strictly worse
# channel, because the tested program also writes there. Two measured defeats
# (2026-08-05_b audit, U21-1/U21-2):
#
#   * julia's last stdout line lacking a trailing newline concatenates the
#     script's own `exit=N` marker onto it, so `^exit=` stops matching and the
#     code falls through to the 125 sentinel -- a PASSING suite recorded
#     `FAIL 125`;
#   * with that in play, `tail -1` then picks up any EARLIER line beginning
#     `exit=` -- and a suite that printed `exit=0` and failed was recorded
#     `PASS 0`, with this script exiting 0.
#
# A gate whose one job is to notice a failing suite must not read its verdict
# from a channel the suite can write. `CODE=$?` immediately after the command
# is the whole fix; the `exit=` line remains in the log for a human reader but
# is no longer load-bearing.

set -u

REPO="$(cd "$(dirname "$0")/.." && pwd)"
JULIA="${OCTOPUS_NIGHTLY_JULIA:-$HOME/.local/bin/julia}"
OUTDIR="$HOME/.octopus_nightly"
STAMP="$(date +%Y%m%d_%H%M%S)"
LOG="$OUTDIR/$STAMP.log"
LOCK="$OUTDIR/lock"

# Resolved with -C rather than after `cd`, so the rows written on the early
# exit paths below still identify the tree they refer to.
COMMIT="$(git -C "$REPO" describe --always --dirty 2>/dev/null || echo unknown)"

# Every exit path past this point appends a row. Four of them used to return
# without one -- lock held, stale-lock reclaim failed, `cd` failed, and an
# unwritable $OUTDIR -- and three of those exited 0, so a wedged or misconfigured
# gate was indistinguishable from a passing run to cron for up to 24 h while
# `status.tsv` simply stopped growing. The only surviving signal was a stale
# date, which nothing checks (2026-08-05_b audit, U21-3/U21-4).
emit_row() {   # verdict, exit code, testsets
    [ -d "$OUTDIR" ] || return 0
    [ -f "$OUTDIR/status.tsv" ] ||
        printf 'date\tcommit\ttestsets\tverdict\texit\n' > "$OUTDIR/status.tsv"
    printf '%s\t%s\t%s\t%s\t%s\n' \
        "$STAMP" "$COMMIT" "${3:-0}" "$1" "$2" >> "$OUTDIR/status.tsv"
}

# The one path that cannot leave a row is an $OUTDIR that will not exist, so it
# is the one path that must be loud on stderr and exit nonzero.
if ! mkdir -p "$OUTDIR" 2>/dev/null; then
    echo "octopus nightly: cannot create $OUTDIR -- no row can be recorded" >&2
    exit 1
fi

# One run at a time; a wedged run older than a day does not block forever.
if ! mkdir "$LOCK" 2>/dev/null; then
    if [ -n "$(find "$OUTDIR" -maxdepth 1 -name lock -mmin +1440)" ]; then
        rmdir "$LOCK" 2>/dev/null
        mkdir "$LOCK" 2>/dev/null || { emit_row LOCKED 0 0; exit 0; }
    else
        emit_row LOCKED 0 0
        exit 0
    fi
fi
trap 'rmdir "$LOCK" 2>/dev/null' EXIT

cd "$REPO" || { emit_row ERROR 1 0; exit 1; }

echo "== octopus nightly suite  $STAMP  commit $COMMIT" > "$LOG"
"$JULIA" --project=. --threads=4 -e \
    'using Pkg; Pkg.test(julia_args=["--threads=4"])' >> "$LOG" 2>&1
CODE=$?
printf '\nexit=%s\n' "$CODE" >> "$LOG"
TESTSETS="$(grep -c '^Test Summary' "$LOG")"
VERDICT=FAIL
[ "$CODE" = "0" ] && VERDICT=PASS

emit_row "$VERDICT" "$CODE" "$TESTSETS"
ln -sfn "$LOG" "$OUTDIR/latest.log"

# Keep the last 14 logs.
ls -1t "$OUTDIR"/*.log 2>/dev/null | grep -v latest | tail -n +15 | xargs -r rm -f

exit "$CODE"
