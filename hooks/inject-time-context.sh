#!/usr/bin/env bash
# inject-time-context.sh — claude-context-tick UserPromptSubmit hook
# https://github.com/DoubleNode/claude-context-tick
# SPDX-License-Identifier: MIT
#
# Injects a <context-tick> line into each Claude Code prompt, but only when
# meaningful state has changed: the first run of a session, a date rollover,
# a quarter-hour boundary, or a timezone shift. This keeps the context fresh
# without spamming every prompt with redundant timestamp noise.
#
# Kill-switch: set CLAUDE_TIME_INJECT=0 in the environment to disable entirely.
# Reads session_id from stdin per the Claude Code UserPromptSubmit contract —
# the harness does NOT export CLAUDE_SESSION_ID to the environment.

set -euo pipefail

# --- Kill-switch (checked before stdin read — early exit is safe) ---
[[ "${CLAUDE_TIME_INJECT:-1}" == "0" ]] && exit 0

# --- Read session_id from stdin JSON (D1 fix) ---
# Claude Code passes hook metadata via stdin, not env vars.
# Consume stdin once; use python3 (already a dependency) for portability.
# D3 fix: sanitize session_id via positive whitelist [A-Za-z0-9._-] so
# untrusted input cannot escape STATE_DIR (e.g. session_id="../etc/passwd").
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
STATE_FILE="${STATE_DIR}/${SESSION_ID}.json"
# D2 fix: silent exit when state dir cannot be created or is not writable.
# The hook is best-effort — if state cannot be persisted, injection is skipped
# rather than spamming the Claude Code UI with stderr.
mkdir -p "$STATE_DIR" 2>/dev/null || exit 0
[[ -w "$STATE_DIR" ]] || exit 0

# --- Lazy GC sweep (runs at most once per 24h) ---
# Returns 0 if a sweep is due (marker absent or >24h old), 1 otherwise.
_gc_sweep_due() {
  local marker="$1"
  if [ ! -f "$marker" ]; then
    return 0
  fi
  python3 -c "
import os, sys, time
try:
    age = time.time() - os.path.getmtime(sys.argv[1])
    sys.exit(0 if age >= 86400 else 1)
except Exception:
    sys.exit(1)
" "$marker" 2>/dev/null
  return $?
}

# Enumerate and remove session state files whose mtime is >7 days old.
# Belt-and-suspenders: the glob *.json already excludes .gc-sweep (no .json
# extension), but the find pattern makes the exclusion explicit.
# Uses find -mtime +7 (floor semantics: files older than 7*24h blocks).
# Never uses find -delete (flag-order footgun per dev-team policy).
# All operations silent; function always returns 0.
_gc_run_sweep() {
  local marker="${STATE_DIR}/.gc-sweep"
  _gc_sweep_due "$marker" 2>/dev/null || return 0
  # Prune stale .json session files; explicitly exclude the marker and .tmp.* files
  find "$STATE_DIR" -maxdepth 1 -name "*.json" \
    ! -name ".gc-sweep" \
    ! -name ".tmp.*" \
    -mtime +7 \
    -print0 2>/dev/null \
    | xargs -0 rm -f 2>/dev/null || true
  # Update marker regardless of whether any files were pruned
  touch "$marker" 2>/dev/null || true
  return 0
}
_gc_run_sweep 2>/dev/null || true

# --- Current values ---
NOW_DATE=$(date +%Y-%m-%d)
NOW_TIME=$(date +%H:%M)
NOW_TZ=$(date +%Z)              # e.g. PDT, UTC, EST
# Linux portability: on some Debian/Ubuntu installs /etc/localtime is a regular
# file, not a symlink; readlink then exits non-zero and set -e aborts the hook.
# Suppress stderr and tolerate failure — fall back to empty IANA, which the
# decision tree treats as a tz-shift-recoverable signal.
NOW_IANA=$(readlink /etc/localtime 2>/dev/null | sed 's|.*/zoneinfo/||' || echo "")
# Quarter-hour bucket: HH:MM-floored-to-15. Hour MUST be included or
# 14:04 and 15:04 collapse to the same key.
NOW_HOUR=$(date +%H)
RAW_MIN=$(date +%-M)
QH_MIN=$(printf "%02d" $(( (RAW_MIN / 15) * 15 )))
QH_KEY="${NOW_HOUR}:${QH_MIN}"

# --- Read prior state ---
PRIOR_DATE=""
PRIOR_QH=""
PRIOR_IANA=""
FIRST_RUN="true"

if [[ -f "$STATE_FILE" ]]; then
  FIRST_RUN="false"
  PRIOR_DATE=$(python3 -c "import json,sys; d=json.load(open('$STATE_FILE')); print(d.get('date',''))" 2>/dev/null || echo "")
  PRIOR_QH=$(python3   -c "import json,sys; d=json.load(open('$STATE_FILE')); print(d.get('qh',''))"   2>/dev/null || echo "")
  PRIOR_IANA=$(python3 -c "import json,sys; d=json.load(open('$STATE_FILE')); print(d.get('iana',''))" 2>/dev/null || echo "")
fi

# --- Decide what to inject ---
INJECT=""
REASON=""

if [[ "$FIRST_RUN" == "true" ]]; then
  INJECT="${NOW_DATE} · ${NOW_TIME} ${NOW_TZ}"
  REASON="first-run"
elif [[ "$NOW_IANA" != "$PRIOR_IANA" ]]; then
  # DST/timezone shift — force full re-inject
  INJECT="${NOW_DATE} · ${NOW_TIME} ${NOW_TZ}"
  REASON="tz-shift"
elif [[ "$NOW_DATE" != "$PRIOR_DATE" ]]; then
  INJECT="${NOW_DATE} · ${NOW_TIME} ${NOW_TZ}"
  REASON="date-rollover"
elif [[ "${NOW_DATE}T${QH_KEY}" != "$PRIOR_QH" ]]; then
  INJECT="${NOW_DATE} · ${NOW_TIME} ${NOW_TZ}"
  REASON="qh-tick"
fi

# --- Write new state (atomic) ---
if [[ -n "$INJECT" ]]; then
  # D2 fix: silent fall-through if mktemp fails (e.g. dir made read-only mid-run).
  # Trap cleans up the .tmp.* orphan on any abnormal exit path before mv.
  TMP=$(mktemp "${STATE_DIR}/.tmp.XXXXXX" 2>/dev/null) || exit 0
  trap 'rm -f "$TMP" 2>/dev/null' EXIT
  python3 - "$TMP" "$NOW_DATE" "${NOW_DATE}T${QH_KEY}" "$NOW_IANA" "$NOW_TZ" "$REASON" <<'PYEOF'
import json, sys
_, tmp, date, qh, iana, tz, reason = sys.argv
data = {
    "date":   date,
    "qh":     qh,
    "iana":   iana,
    "tz":     tz,
    "reason": reason
}
with open(tmp, "w") as f:
    json.dump(data, f)
PYEOF
  mv "$TMP" "$STATE_FILE"

  # Emit injection via UserPromptSubmit protocol (D2 fix)
  # Canonical schema per Claude Code hooks docs:
  # {"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"..."}}
  python3 -c "
import json, sys
context_text = '<context-tick>' + sys.argv[1] + '</context-tick>'
payload = {
    'hookSpecificOutput': {
        'hookEventName': 'UserPromptSubmit',
        'additionalContext': context_text
    }
}
print(json.dumps(payload))
" "$INJECT"
fi

# Liveness signal: keep state file mtime fresh so the GC sweep does not expire
# an active session. Runs even when INJECT is empty (no state change this prompt).
# MUST be after FIRST_RUN detection and after the state-write block — placing it
# before FIRST_RUN would pre-create STATE_FILE and break first-run injection.
touch "$STATE_FILE" 2>/dev/null || true

exit 0
