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
# date, commit (--dirty marked), testset count, PASS/FAIL, exit code.
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

mkdir -p "$OUTDIR"

# One run at a time; a wedged run older than a day does not block forever.
if ! mkdir "$LOCK" 2>/dev/null; then
    if [ -n "$(find "$OUTDIR" -maxdepth 1 -name lock -mmin +1440)" ]; then
        rmdir "$LOCK" 2>/dev/null
        mkdir "$LOCK" 2>/dev/null || exit 0
    else
        exit 0
    fi
fi
trap 'rmdir "$LOCK" 2>/dev/null' EXIT

cd "$REPO" || exit 1
COMMIT="$(git describe --always --dirty 2>/dev/null || echo unknown)"

echo "== octopus nightly suite  $STAMP  commit $COMMIT" > "$LOG"
"$JULIA" --project=. --threads=4 -e \
    'using Pkg; Pkg.test(julia_args=["--threads=4"])' >> "$LOG" 2>&1
CODE=$?
printf '\nexit=%s\n' "$CODE" >> "$LOG"
TESTSETS="$(grep -c '^Test Summary' "$LOG")"
VERDICT=FAIL
[ "$CODE" = "0" ] && VERDICT=PASS

[ -f "$OUTDIR/status.tsv" ] ||
    printf 'date\tcommit\ttestsets\tverdict\texit\n' > "$OUTDIR/status.tsv"
printf '%s\t%s\t%s\t%s\t%s\n' \
    "$STAMP" "$COMMIT" "$TESTSETS" "$VERDICT" "$CODE" >> "$OUTDIR/status.tsv"
ln -sfn "$LOG" "$OUTDIR/latest.log"

# Keep the last 14 logs.
ls -1t "$OUTDIR"/*.log 2>/dev/null | grep -v latest | tail -n +15 | xargs -r rm -f

exit "$CODE"
