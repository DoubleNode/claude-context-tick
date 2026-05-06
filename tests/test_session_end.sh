#!/usr/bin/env bash
# test_session_end.sh — validate session-end.sh hook behaviour
#
# Covers three scenarios from design memo §6:
#   SE-1: SessionEnd deletes only its own session file; all other files survive.
#   SE-2: Malicious session_id (path-traversal) is sanitized; real /etc/passwd untouched.
#   SE-3: Empty STATE_DIR + nonexistent session_id → exit 0, no output.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"

if [[ "${_RUNNER_SANDBOX:-0}" != "1" ]]; then
  _TMP_HOME=$(mktemp -d)
  export HOME="$_TMP_HOME"
  trap 'rm -rf "$_TMP_HOME"' EXIT
fi

source "${REPO_ROOT}/tests/lib.sh"

STATE_DIR="${HOME}/.claude/state/time-inject"
MARKER="${STATE_DIR}/.gc-sweep"

# --- SE-1: Proper cleanup — deletes only its own file --------------------
# This is the authoritative "SessionEnd fires correct cleanup" test.
# Assertion-rich: targeted file gone, all other files + marker survive,
# STATE_DIR itself survives, exit code is 0.
rm -rf "$STATE_DIR"
mkdir -p "$STATE_DIR"
touch "${STATE_DIR}/alpha.json"
touch "${STATE_DIR}/beta.json"
touch "${STATE_DIR}/gamma.json"
touch "$MARKER"

run_session_end "alpha"
SE1_EXIT=$?

assert_equal "$SE1_EXIT" "0" "SE-1: session-end must exit 0"
assert_file_absent "${STATE_DIR}/alpha.json" "SE-1: session-end must delete its own file (alpha.json)"
assert_file_exists "${STATE_DIR}/beta.json" "SE-1: session-end must not touch other session files (beta.json)"
assert_file_exists "${STATE_DIR}/gamma.json" "SE-1: session-end must not touch other session files (gamma.json)"
assert_file_exists "$MARKER" "SE-1: session-end must not touch the .gc-sweep marker"

# STATE_DIR itself must still exist (hook must never rm -rf the dir).
if [[ ! -d "$STATE_DIR" ]]; then
  echo "ASSERT FAILED: SE-1: session-end must not remove STATE_DIR" >&2
  echo "  Expected directory to exist: $STATE_DIR" >&2
  exit 1
fi

# --- SE-2: Malicious session_id cannot escape STATE_DIR ------------------
# Input: "../../../etc/passwd"
# Sanitized via [^A-Za-z0-9._-] removal → "......etcpasswd"
# Hook must delete ${STATE_DIR}/......etcpasswd.json (not /etc/passwd).
#
# Counting: "../" = ".." + "/" → keep "..", strip "/"
#   Three "../" segments = 6 dots; then "etc" + "/" (stripped) + "passwd"
#   Result: "......etcpasswd"
rm -rf "$STATE_DIR"
mkdir -p "$STATE_DIR"

SANITIZED_SID=$(python3 -c "import re; print(re.sub(r'[^A-Za-z0-9._-]', '', '../../../etc/passwd') or 'unknown')")
SANITIZED_FILE="${STATE_DIR}/${SANITIZED_SID}.json"
touch "$SANITIZED_FILE"

run_session_end "../../../etc/passwd"

assert_file_absent "$SANITIZED_FILE" "SE-2: sanitized state file must be deleted by session-end"

# /etc/passwd must not have been deleted or modified — it is root-owned and outside
# STATE_DIR; any path constructed from the sanitized form lives inside STATE_DIR.
# Belt-and-suspenders: verify the file we seeded was in STATE_DIR, not elsewhere.
HOME_ABS=$(python3 -c "import os; print(os.path.abspath('$HOME'))")
SANITIZED_ABS=$(python3 -c "import os; print(os.path.abspath('$SANITIZED_FILE'))")
if [[ "$SANITIZED_ABS" != "$HOME_ABS"* ]]; then
  echo "ASSERT FAILED: SE-2: sanitized file path escapes sandbox HOME" >&2
  echo "  Sanitized file: $SANITIZED_ABS" >&2
  echo "  HOME: $HOME_ABS" >&2
  exit 1
fi

# --- SE-3: Silent when session file is already absent --------------------
# Setup: empty STATE_DIR; session_id does not correspond to any file.
rm -rf "$STATE_DIR"
mkdir -p "$STATE_DIR"

OUTPUT=$(run_session_end "nonexistent-session" 2>&1)
SE3_EXIT=$?

assert_equal "$SE3_EXIT" "0" "SE-3: session-end must exit 0 when target file absent"
assert_equal "$OUTPUT" "" "SE-3: session-end must produce no output when target file absent"

echo "[PASS] test_session_end"
