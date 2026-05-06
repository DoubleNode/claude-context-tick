#!/usr/bin/env bash
# test_kill_switch.sh — CLAUDE_TIME_INJECT=0 suppresses all output and state writes
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"

if [[ "${_RUNNER_SANDBOX:-0}" != "1" ]]; then
  _TMP_HOME=$(mktemp -d)
  export HOME="$_TMP_HOME"
  trap 'rm -rf "$_TMP_HOME"' EXIT
fi

source "${REPO_ROOT}/tests/lib.sh"

SID="test-kill-switch-session"
STATE_FILE="${HOME}/.claude/state/time-inject/${SID}.json"

# --- Kill-switch ON: must produce zero output and no state file ---
OUTPUT=$(CLAUDE_TIME_INJECT=0 run_hook "$SID")
assert_equal "$OUTPUT" "" "kill-switch=0 must produce no output"
assert_file_absent "$STATE_FILE" "kill-switch=0 must not create state file"

# --- Kill-switch OFF (unset / default): must inject normally ---
OUTPUT2=$(run_hook "$SID")
assert_contains "$OUTPUT2" "<context-tick>" "kill-switch unset must produce context-tick on first run"
assert_file_exists "$STATE_FILE" "kill-switch unset must create state file on first run"

echo "[PASS] test_kill_switch"
