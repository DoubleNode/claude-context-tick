#!/usr/bin/env bash
# test_gc_sweep.sh — validate lazy GC sweep in inject-time-context.sh
#
# Covers four scenarios from design memo §6:
#   GC-1: Fresh files survive sweep (mtime now).
#   GC-2: Stale file (mtime 8 days ago) is removed; recent file survives.
#   GC-3: Rate-limit: fresh marker → sweep skipped, stale file survives.
#   GC-4: Sweep never removes the .gc-sweep marker itself.
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

# Compute an 8-day-ago timestamp portably (macOS BSD + Linux GNU safe).
# touch -t requires YYYYMMDDhhmm format; python3 datetime handles both platforms.
OLD_TSTAMP=$(python3 -c "
import datetime
d = datetime.datetime.now() - datetime.timedelta(days=8)
print(d.strftime('%Y%m%d%H%M'))
")

# Helper: stamp the sweep marker as stale (2025-01-01 00:00 — well past 24h).
_marker_stale() {
  mkdir -p "$STATE_DIR"
  touch -t 202501010000 "$MARKER"
}

# Helper: stamp the sweep marker as fresh (now).
_marker_fresh() {
  mkdir -p "$STATE_DIR"
  touch "$MARKER"
}

# --- GC-1: Fresh files survive a sweep ------------------------------------
# Setup: three session files with mtime NOW; marker is absent (sweep will run).
rm -rf "$STATE_DIR"
mkdir -p "$STATE_DIR"
touch "${STATE_DIR}/session-a.json"
touch "${STATE_DIR}/session-b.json"
touch "${STATE_DIR}/session-c.json"
# No marker — sweep is due.

run_hook "gc1-trigger-session" >/dev/null

assert_file_exists "${STATE_DIR}/session-a.json" "GC-1: fresh file session-a.json must survive sweep"
assert_file_exists "${STATE_DIR}/session-b.json" "GC-1: fresh file session-b.json must survive sweep"
assert_file_exists "${STATE_DIR}/session-c.json" "GC-1: fresh file session-c.json must survive sweep"
assert_file_exists "$MARKER" "GC-1: sweep must create/update .gc-sweep marker"

# --- GC-2: Stale file removed; recent file survives -----------------------
# Setup: one old file (8 days ago), one recent file; marker is stale (sweep due).
rm -rf "$STATE_DIR"
mkdir -p "$STATE_DIR"
touch "${STATE_DIR}/session-old.json"
touch -t "$OLD_TSTAMP" "${STATE_DIR}/session-old.json"
touch "${STATE_DIR}/session-recent.json"
_marker_stale

run_hook "gc2-trigger-session" >/dev/null

assert_file_absent "${STATE_DIR}/session-old.json" "GC-2: stale file must be removed by sweep"
assert_file_exists "${STATE_DIR}/session-recent.json" "GC-2: recent file must survive sweep"

# --- GC-3: Rate-limit prevents re-sweep when marker is fresh --------------
# Setup: stale session file; marker mtime = NOW (within 24h window).
rm -rf "$STATE_DIR"
mkdir -p "$STATE_DIR"
touch "${STATE_DIR}/session-stale.json"
touch -t "$OLD_TSTAMP" "${STATE_DIR}/session-stale.json"
_marker_fresh

run_hook "gc3-trigger-session" >/dev/null

assert_file_exists "${STATE_DIR}/session-stale.json" "GC-3: stale file must NOT be removed when marker is fresh (rate-limit active)"

# --- GC-4: Sweep never removes the .gc-sweep marker ----------------------
# Setup: no session files; marker is stale so sweep will run.
rm -rf "$STATE_DIR"
mkdir -p "$STATE_DIR"
_marker_stale

run_hook "gc4-trigger-session" >/dev/null

assert_file_exists "$MARKER" "GC-4: .gc-sweep marker must survive the sweep"

echo "[PASS] test_gc_sweep"
