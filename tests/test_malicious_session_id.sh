#!/usr/bin/env bash
# test_malicious_session_id.sh — session_id sanitization prevents path traversal
#
# The hook sanitizes session_id via: re.sub(r'[^A-Za-z0-9._-]', '', sid)
# Characters in whitelist: A-Z a-z 0-9 . _ -
# Characters stripped:     / (slash), spaces, @, etc.
#
# Input "../../../etc/passwd":
#   Stripped chars: / (three times, at positions between segments)
#   Retained chars: . . . e t c p a s s w d  (dots and alphanumeric)
#   Result:         "....etcpasswd"  (four dots from "../../..") + "etcpasswd"
#   Wait — let's be precise:
#     "../../../etc/passwd"
#     . . / . . / . . / e t c / p a s s w d
#     After stripping /: . . . . . . e t c p a s s w d
#     = "......etcpasswd"
#   Counting: "../" = ".." then "/" → keep ".." (2 dots), strip "/"
#             three segments of "../" = 6 dots + "etc" + "passwd" after final "/"
#   So sanitized = "......etcpasswd"
#   (We verify the state file is INSIDE the sandbox, not /etc/passwd)
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
HOOK="${REPO_ROOT}/hooks/inject-time-context.sh"

# --- Test 1: path-traversal session_id ---
TRAVERSAL_SID="../../../etc/passwd"
INPUT_JSON=$(printf '{"session_id":"%s","hook_event_name":"UserPromptSubmit"}' "$TRAVERSAL_SID")

OUTPUT=$(bash "$HOOK" <<< "$INPUT_JSON")

# The hook must NOT have written to /etc/passwd (it almost certainly cannot, but
# we verify the state dir contains only safe files).
# The real /etc/passwd is owned by root and not in our sandbox HOME — verify
# that whatever file was created lives strictly inside STATE_DIR.
SANITIZED_SID=$(python3 -c "import re; print(re.sub(r'[^A-Za-z0-9._-]', '', '../../../etc/passwd') or 'unknown')")
EXPECTED_STATE_FILE="${STATE_DIR}/${SANITIZED_SID}.json"

# Must inject (first run).
assert_contains "$OUTPUT" "<context-tick>" "path-traversal session_id must still produce injection"

# State file must be inside HOME (not /etc/passwd or any path outside sandbox).
assert_file_exists "$EXPECTED_STATE_FILE" "sanitized state file must exist inside HOME"

# /etc/passwd must NOT have been written to (it predates this test and is root-owned;
# any write would have failed — but we assert the file path we expect is safe).
ACTUAL_STATE_PATH=$(python3 -c "
import os, sys
f = open('$EXPECTED_STATE_FILE')
# Just confirm it opens — the real assertion is that its path is inside HOME.
print(os.path.abspath('$EXPECTED_STATE_FILE'))
")
HOME_ABS=$(python3 -c "import os; print(os.path.abspath('$HOME'))")
if [[ "$ACTUAL_STATE_PATH" != "$HOME_ABS"* ]]; then
  echo "ASSERT FAILED: state file path escapes sandbox HOME" >&2
  echo "  State file: $ACTUAL_STATE_PATH" >&2
  echo "  HOME: $HOME_ABS" >&2
  exit 1
fi

# --- Test 2: null / missing session_id → falls back to "unknown" ---
NULL_INPUT='{"hook_event_name":"UserPromptSubmit"}'
OUTPUT2=$(bash "$HOOK" <<< "$NULL_INPUT")
assert_contains "$OUTPUT2" "<context-tick>" "missing session_id must produce injection (fallback to unknown)"

UNKNOWN_STATE_FILE="${STATE_DIR}/unknown.json"
assert_file_exists "$UNKNOWN_STATE_FILE" "missing session_id must create unknown.json"

echo "[PASS] test_malicious_session_id"
