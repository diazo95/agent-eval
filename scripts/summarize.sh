#!/usr/bin/env bash
# Extract the reportable numbers from a committed test log.
#
# Usage: scripts/summarize.sh <repo>
#
# Reads logs/<repo>-test.log and prints the pytest summary line plus the
# per-outcome counts parsed from it. Parsing the log (rather than adding
# --junitxml to the run) keeps the graded command byte-identical to what the
# project documents.

set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO="${1:?repo required}"
LOG="$ROOT/logs/$REPO-test.log"

[ -f "$LOG" ] || { echo "no log: $LOG" >&2; exit 1; }

echo "== $REPO =="
echo "-- HEAD --"
grep -oE '^[0-9a-f]{40}' "$ROOT/logs/$REPO-clone.log" | head -1

echo "-- harness exit / elapsed --"
grep -E '^### (EXIT|ELAPSED_SEC|TIMEOUT_CAP_SEC):' "$LOG"

echo "-- pytest summary line --"
# The final "=== N passed, M failed ... in Xs ===" banner.
summary=$(grep -E '^=+ .*(passed|failed|error|no tests ran).* =+$' "$LOG" | tail -1)
echo "${summary:-<none found>}"

echo "-- parsed counts --"
for k in passed failed skipped error errors deselected xfailed xpassed; do
  n=$(printf '%s' "$summary" | grep -oE "[0-9]+ $k\b" | grep -oE '^[0-9]+' | head -1)
  [ -n "$n" ] && echo "$k=$n"
done

echo "-- collected --"
grep -E '^collected [0-9]+|^[0-9]+ tests collected|collected [0-9]+ items' "$LOG" | tail -2

echo "-- skip reasons mentioning key/network/cluster --"
grep -iE 'SKIPPED.*(api|key|network|cluster|kube|token|credential)' "$LOG" | sort | uniq -c | sort -rn | head -15
