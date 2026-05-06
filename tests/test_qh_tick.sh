#!/usr/bin/env bash
# test_qh_tick.sh — hook injects when stored QH bucket is stale
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"

if [[ "${_RUNNER_SANDBOX:-0}" != "1" ]]; then
  _TMP_HOME=$(mktemp -d)
  export HOME="$_TMP_HOME"
  trap 'rm -rf "$_TMP_HOME"' EXIT
fi

source "${REPO_ROOT}/tests/lib.sh"

SID="test-qh-tick-session"
STATE_DIR="${HOME}/.claude/state/time-inject"
STATE_FILE="${STATE_DIR}/${SID}.json"

TODAY=$(date +%Y-%m-%d)
NOW_IANA=$(readlink /etc/localtime 2>/dev/null | sed 's|.*/zoneinfo/||' || echo "")

# Use a deliberately stale QH bucket (far in the past) so the current QH bucket
# is guaranteed to differ, regardless of wall-clock time.
STALE_QH="2020-01-01T00:00"

# Pre-populate state file with today's date but a stale QH.
mkdir -p "$STATE_DIR"
python3 - "$STATE_FILE" "$TODAY" "$STALE_QH" "$NOW_IANA" "first-run" <<'PYEOF'
import json, sys
_, state_file, date, qh, iana, reason = sys.argv
data = {"date": date, "qh": qh, "iana": iana, "reason": reason}
with open(state_file, "w") as f:
    json.dump(data, f)
PYEOF

# Run the hook — must detect QH tick.
OUTPUT=$(run_hook "$SID")
assert_contains "$OUTPUT" "<context-tick>" "stale qh bucket must trigger injection"

# State file must now carry reason=qh-tick.
NEW_REASON=$(python3 -c "import json; d=json.load(open('$STATE_FILE')); print(d.get('reason',''))")
assert_equal "$NEW_REASON" "qh-tick" "state file reason must be 'qh-tick'"

# QH value in state file must NOT still be the stale value.
NEW_QH=$(python3 -c "import json; d=json.load(open('$STATE_FILE')); print(d.get('qh',''))")
if [[ "$NEW_QH" == "$STALE_QH" ]]; then
  echo "ASSERT FAILED: state file qh was not updated (still $STALE_QH)" >&2
  exit 1
fi

echo "[PASS] test_qh_tick"
