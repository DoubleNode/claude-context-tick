#!/usr/bin/env bash
# test_tz_shift.sh — hook injects when stored IANA zone differs from current zone
#
# NOTE on Linux runners: /etc/localtime may be a regular file (not a symlink).
# In that case `readlink /etc/localtime` returns empty string, and the hook also
# stores an empty IANA value. We store a non-empty IANA in the state file so that
# empty-string != "America/New_York" still triggers the tz-shift branch. This
# correctly exercises the code path on both macOS (where readlink succeeds) and
# Linux (where it returns empty).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"

if [[ "${_RUNNER_SANDBOX:-0}" != "1" ]]; then
  _TMP_HOME=$(mktemp -d)
  export HOME="$_TMP_HOME"
  trap 'rm -rf "$_TMP_HOME"' EXIT
fi

source "${REPO_ROOT}/tests/lib.sh"

SID="test-tz-shift-session"
STATE_DIR="${HOME}/.claude/state/time-inject"
STATE_FILE="${STATE_DIR}/${SID}.json"

TODAY=$(date +%Y-%m-%d)

# Detect the current IANA zone. On Linux this may be empty if /etc/localtime is
# a regular file rather than a symlink — that is fine; empty != stored value.
NOW_IANA=$(readlink /etc/localtime 2>/dev/null | sed 's|.*/zoneinfo/||' || echo "")

# Choose a "prior" IANA that is guaranteed to differ from the current IANA.
# If the system is already America/New_York, use Europe/London instead.
if [[ "$NOW_IANA" == "America/New_York" ]]; then
  PRIOR_IANA="Europe/London"
else
  PRIOR_IANA="America/New_York"
fi

# NOW_IANA on Linux may be empty; PRIOR_IANA ("America/New_York" or "Europe/London")
# is always non-empty, so NOW_IANA != PRIOR_IANA is guaranteed.

# Pre-populate state file with the prior (different) IANA zone.
mkdir -p "$STATE_DIR"
python3 - "$STATE_FILE" "$TODAY" "${TODAY}T00:00" "$PRIOR_IANA" "first-run" <<'PYEOF'
import json, sys
_, state_file, date, qh, iana, reason = sys.argv
data = {"date": date, "qh": qh, "iana": iana, "reason": reason}
with open(state_file, "w") as f:
    json.dump(data, f)
PYEOF

# Run the hook — must detect tz-shift.
OUTPUT=$(run_hook "$SID")
assert_contains "$OUTPUT" "<context-tick>" "tz-shift must trigger injection"

# State file must now carry reason=tz-shift.
NEW_REASON=$(python3 -c "import json; d=json.load(open('$STATE_FILE')); print(d.get('reason',''))")
assert_equal "$NEW_REASON" "tz-shift" "state file reason must be 'tz-shift'"

# Stored IANA must now reflect the current zone (not the old prior).
NEW_IANA=$(python3 -c "import json; d=json.load(open('$STATE_FILE')); print(d.get('iana',''))")
assert_equal "$NEW_IANA" "$NOW_IANA" "state file iana must be updated to current zone after tz-shift"

echo "[PASS] test_tz_shift"
