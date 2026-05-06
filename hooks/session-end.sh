#!/usr/bin/env bash
# session-end.sh — claude-context-tick SessionEnd hook
# https://github.com/DoubleNode/claude-context-tick
# SPDX-License-Identifier: MIT
#
# Removes this session's state file when SessionEnd fires.
# Complementary to the lazy sweep in inject-time-context.sh: the sweep prunes
# files from sessions that ended without firing this hook (e.g. hard kills,
# crashes); this hook provides prompt, precise cleanup for normal exits.
#
# No kill-switch check — cleanup runs even when CLAUDE_TIME_INJECT=0.
# No set -euo pipefail — pure cleanup, must never exit non-zero.

# --- Read session_id from stdin JSON ---
# Verbatim copy of inject-time-context.sh lines 25-33.
STDIN_JSON=$(cat)
SESSION_ID=$(printf '%s' "$STDIN_JSON" | python3 -c \
  "import sys,json,re
try:
    sid = json.load(sys.stdin).get('session_id','unknown')
except Exception:
    sid = 'unknown'
sid = re.sub(r'[^A-Za-z0-9._-]', '', sid) or 'unknown'
print(sid)" 2>/dev/null || echo "unknown")

STATE_DIR="${HOME}/.claude/state/time-inject"
TARGET="${STATE_DIR}/${SESSION_ID}.json"

rm -f "$TARGET" 2>/dev/null || true

exit 0
