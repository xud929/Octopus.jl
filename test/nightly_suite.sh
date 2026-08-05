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
# The suite's own exit code is the verdict; the trailing-pipe trap that once
# masked a failing run (Measured Lesson 9) is why the code is captured
# before any postprocessing.

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

{
    echo "== octopus nightly suite  $STAMP  commit $COMMIT"
    "$JULIA" --project=. --threads=4 -e \
        'using Pkg; Pkg.test(julia_args=["--threads=4"])'
    echo "exit=$?"
} > "$LOG" 2>&1

CODE="$(sed -n 's/^exit=//p' "$LOG" | tail -1)"
[ -n "$CODE" ] || CODE=125
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
