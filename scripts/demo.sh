#!/usr/bin/env bash
# demo.sh — claude-context-tick mechanism demo
# https://github.com/DoubleNode/claude-context-tick
#
# Shows the gating logic in four scenes:
#   1. First run of a "session"  → INJECTS  <context-tick>...</context-tick>
#   2. Same session, no time advance → SILENT (state matches)
#   3. Fast-forward state by one quarter-hour
#   4. Re-run → INJECTS again (qh-tick trigger fired)
#
# Designed to be recorded with asciinema:
#   asciinema rec -i 2 demo.cast -c "bash scripts/demo.sh"
#   asciinema upload demo.cast
#
# The `-i 2` flag caps idle-time stretches at 2 sec so the cast plays
# tight without losing the deliberate pacing.

set -euo pipefail

# -----------------------------------------------------------------------------
# Paths
# -----------------------------------------------------------------------------
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="${REPO_ROOT}/hooks/inject-time-context.sh"
STATE_DIR="${HOME}/.claude/state/time-inject"
SESSION="demo-$(date +%s)"
STATE_FILE="${STATE_DIR}/${SESSION}.json"

# -----------------------------------------------------------------------------
# Visual helpers
# -----------------------------------------------------------------------------
# Color (only if stdout is a TTY — keeps cast files clean if piped)
if [ -t 1 ]; then
  C_PROMPT='\033[1;36m'   # cyan
  C_COMMENT='\033[2;37m'  # dim gray
  C_OUT='\033[1;33m'      # yellow (injected line stands out)
  C_RESET='\033[0m'
else
  C_PROMPT=''; C_COMMENT=''; C_OUT=''; C_RESET=''
fi

# Print a comment line (narration)
say() { printf "${C_COMMENT}# %s${C_RESET}\n" "$1"; sleep 0.6; }

# Print a fake prompt + command, then run it
run() {
  local cmd="$1"
  printf "${C_PROMPT}\$${C_RESET} %s\n" "$cmd"
  sleep 0.4
  # Run via bash -c so the displayed string and executed string match exactly
  printf "${C_OUT}"
  bash -c "$cmd" || true
  printf "${C_RESET}"
  sleep 0.8
}

# Cross-platform "date 16 minutes ago" — handles BSD/macOS and GNU/Linux
date_minus_16m_qh() {
  # We want to compute a quarter-hour boundary at least 16 min in the past
  # so the rewritten state is guaranteed to differ from the current qh.
  if date -v-16M +%Y-%m-%dT%H:%M >/dev/null 2>&1; then
    # BSD/macOS
    date -v-16M "+%Y-%m-%dT%H:%M"
  else
    # GNU/Linux
    date -d '16 minutes ago' "+%Y-%m-%dT%H:%M"
  fi
}

# -----------------------------------------------------------------------------
# Cleanup on exit (always — even on Ctrl-C)
# -----------------------------------------------------------------------------
cleanup() { rm -f "$STATE_FILE"; }
trap cleanup EXIT INT TERM

# -----------------------------------------------------------------------------
# Demo
# -----------------------------------------------------------------------------
clear

say "claude-context-tick: tiny ground-truth time, only when state changes."
say "the hook prints a JSON envelope the Claude Code harness consumes;"
say "the 'additionalContext' field is what lands in the conversation."
echo

say "Scene 1 — first run of a session. Injects."
run "echo '{\"session_id\":\"${SESSION}\"}' | bash hooks/inject-time-context.sh"
echo

say "Scene 2 — same session, same minute. Silent (nothing to add)."
run "echo '{\"session_id\":\"${SESSION}\"}' | bash hooks/inject-time-context.sh"
echo

say "Scene 3 — fast-forward state by one quarter-hour."
PAST_QH="$(date_minus_16m_qh)"
run "python3 -c 'import json,sys; s=json.load(open(\"${STATE_FILE}\")); s[\"qh\"]=\"${PAST_QH}\"; json.dump(s,open(\"${STATE_FILE}\",\"w\"))'"
echo

say "Scene 4 — re-run. Quarter-hour boundary crossed. Injects again."
run "echo '{\"session_id\":\"${SESSION}\"}' | bash hooks/inject-time-context.sh"
echo

say "github.com/DoubleNode/claude-context-tick"
sleep 1.2
