#!/usr/bin/env bash
# test_date_rollover.sh — hook injects when stored date is yesterday
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"

if [[ "${_RUNNER_SANDBOX:-0}" != "1" ]]; then
  _TMP_HOME=$(mktemp -d)
  export HOME="$_TMP_HOME"
  trap 'rm -rf "$_TMP_HOME"' EXIT
fi

source "${REPO_ROOT}/tests/lib.sh"

SID="test-date-rollover-session"
STATE_DIR="${HOME}/.claude/state/time-inject"
STATE_FILE="${STATE_DIR}/${SID}.json"

# Compute yesterday portably (macOS vs Linux).
if date -v-1d +%Y-%m-%d &>/dev/null; then
  YESTERDAY=$(date -v-1d +%Y-%m-%d)   # macOS BSD date
else
  YESTERDAY=$(date -d 'yesterday' +%Y-%m-%d)  # GNU date (Linux)
fi

TODAY=$(date +%Y-%m-%d)
NOW_IANA=$(readlink /etc/localtime 2>/dev/null | sed 's|.*/zoneinfo/||' || echo "")

# Pre-populate state file with yesterday's date so the hook sees a date rollover.
mkdir -p "$STATE_DIR"
python3 - "$STATE_FILE" "$YESTERDAY" "${YESTERDAY}T00:00" "$NOW_IANA" "first-run" <<'PYEOF'
import json, sys
_, state_file, date, qh, iana, reason = sys.argv
data = {"date": date, "qh": qh, "iana": iana, "reason": reason}
with open(state_file, "w") as f:
    json.dump(data, f)
PYEOF

# Run the hook — must detect date rollover.
OUTPUT=$(run_hook "$SID")
assert_contains "$OUTPUT" "<context-tick>" "date-rollover must trigger injection"

# State file must now carry today's date and reason=date-rollover.
NEW_DATE=$(python3 -c "import json; d=json.load(open('$STATE_FILE')); print(d.get('date',''))")
NEW_REASON=$(python3 -c "import json; d=json.load(open('$STATE_FILE')); print(d.get('reason',''))")

assert_equal "$NEW_DATE" "$TODAY" "state file date must be updated to today after rollover"
assert_equal "$NEW_REASON" "date-rollover" "state file reason must be 'date-rollover'"

echo "[PASS] test_date_rollover"
