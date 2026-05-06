#!/usr/bin/env bash
# test_state_tracking.sh — verify second call within same QH bucket produces no output
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"

if [[ "${_RUNNER_SANDBOX:-0}" != "1" ]]; then
  _TMP_HOME=$(mktemp -d)
  export HOME="$_TMP_HOME"
  trap 'rm -rf "$_TMP_HOME"' EXIT
fi

source "${REPO_ROOT}/tests/lib.sh"

SID="test-state-tracking-session"
STATE_FILE="${HOME}/.claude/state/time-inject/${SID}.json"

# --- First call: must inject ---
OUTPUT1=$(run_hook "$SID")
assert_contains "$OUTPUT1" "<context-tick>" "first call must inject context-tick"
assert_file_exists "$STATE_FILE" "state file must be created after first call"

# --- Verify state file carries reason=first-run ---
REASON=$(python3 -c "import json; d=json.load(open('$STATE_FILE')); print(d.get('reason',''))")
assert_equal "$REASON" "first-run" "state file must record reason=first-run"

# --- Second call: must produce no output (same session, same QH bucket, same date) ---
# We force the state file's qh to match the current bucket so the second call sees
# no change — this is the correct behavior test independent of wall-clock timing.
NOW_DATE=$(date +%Y-%m-%d)
NOW_HOUR=$(date +%H)
RAW_MIN=$(date +%-M 2>/dev/null || date +%M | sed 's/^0*//')
RAW_MIN=${RAW_MIN:-0}
QH_MIN=$(printf "%02d" $(( (RAW_MIN / 15) * 15 )))
CURRENT_QH="${NOW_DATE}T${NOW_HOUR}:${QH_MIN}"
NOW_IANA=$(readlink /etc/localtime 2>/dev/null | sed 's|.*/zoneinfo/||' || echo "")

python3 - "$STATE_FILE" "$NOW_DATE" "$CURRENT_QH" "$NOW_IANA" "first-run" <<'PYEOF'
import json, sys
_, state_file, date, qh, iana, reason = sys.argv
data = {"date": date, "qh": qh, "iana": iana, "reason": reason}
with open(state_file, "w") as f:
    json.dump(data, f)
PYEOF

OUTPUT2=$(run_hook "$SID")
assert_equal "$OUTPUT2" "" "second call in same QH bucket must produce no output"

echo "[PASS] test_state_tracking"
