#!/usr/bin/env bash
# test_first_run.sh — verify hook injects on first run and creates state file
set -euo pipefail

# Support standalone invocation: locate repo root relative to this file.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"

# Standalone sandbox: if HOME is not already a temp dir (i.e. not set by the runner),
# create one. The runner exports a sandboxed HOME before sourcing this file.
if [[ "${_RUNNER_SANDBOX:-0}" != "1" ]]; then
  _TMP_HOME=$(mktemp -d)
  export HOME="$_TMP_HOME"
  trap 'rm -rf "$_TMP_HOME"' EXIT
fi

# shellcheck source=tests/lib.sh
source "${REPO_ROOT}/tests/lib.sh"

HOOK="${REPO_ROOT}/hooks/inject-time-context.sh"
SID="test-first-run-session"
STATE_FILE="${HOME}/.claude/state/time-inject/${SID}.json"

# Pre-condition: state file must not exist.
assert_file_absent "$STATE_FILE" "state file must not exist before first run"

# Run the hook.
OUTPUT=$(run_hook "$SID")

# Assertions.
assert_contains "$OUTPUT" "<context-tick>" "output must contain <context-tick> on first run"
assert_file_exists "$STATE_FILE" "state file must be created on first run"

# State file must record reason=first-run.
REASON=$(python3 -c "import json; d=json.load(open('$STATE_FILE')); print(d.get('reason',''))")
assert_equal "$REASON" "first-run" "state file reason must be 'first-run'"

echo "[PASS] test_first_run"
