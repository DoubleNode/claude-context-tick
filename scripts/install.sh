#!/usr/bin/env bash
# install.sh — claude-context-tick installer
#
# Registers inject-time-context.sh as a UserPromptSubmit hook and
# session-end.sh as a SessionEnd hook in ~/.claude/settings.json
# without clobbering any existing hooks.
#
# Usage:
#   bash scripts/install.sh
#   CLAUDE_CONTEXT_TICK_DIR=/custom/path bash scripts/install.sh
#
# Dependencies: bash 3.2+, jq, python3

set -euo pipefail

# ---------------------------------------------------------------------------
# Resolve paths
# ---------------------------------------------------------------------------
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
REPO_ROOT="$( cd "$SCRIPT_DIR/.." && pwd )"
HOOK_SRC="$REPO_ROOT/hooks/inject-time-context.sh"
SESSION_END_SRC="$REPO_ROOT/hooks/session-end.sh"

INSTALL_DIR="${CLAUDE_CONTEXT_TICK_DIR:-$HOME/.claude/hooks}"
SETTINGS_FILE="$HOME/.claude/settings.json"

HOOK_NAME="inject-time-context.sh"
HOOK_DEST="$INSTALL_DIR/$HOOK_NAME"

SESSION_END_NAME="session-end.sh"
SESSION_END_DEST="$INSTALL_DIR/$SESSION_END_NAME"

# ---------------------------------------------------------------------------
# Pre-flight checks
# ---------------------------------------------------------------------------
preflight_fail=0

check_dep() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "ERROR: Required dependency not found on PATH: $cmd" >&2
    preflight_fail=1
  fi
}

check_dep jq
check_dep python3
check_dep bash

if [ "$preflight_fail" -ne 0 ]; then
  echo "" >&2
  echo "Install aborted — install missing dependencies and retry." >&2
  exit 1
fi

if [ ! -f "$HOOK_SRC" ]; then
  echo "ERROR: Hook source not found: $HOOK_SRC" >&2
  echo "Run install.sh from inside the claude-context-tick repository." >&2
  exit 1
fi

if [ ! -f "$SESSION_END_SRC" ]; then
  echo "ERROR: Hook source not found: $SESSION_END_SRC" >&2
  echo "Run install.sh from inside the claude-context-tick repository." >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Install hook script
# ---------------------------------------------------------------------------
mkdir -p "$INSTALL_DIR"

cp "$HOOK_SRC" "$HOOK_DEST"
chmod +x "$HOOK_DEST"

echo "Installed hook: $HOOK_DEST"

cp "$SESSION_END_SRC" "$SESSION_END_DEST"
chmod +x "$SESSION_END_DEST"

echo "Installed hook: $SESSION_END_DEST"

# ---------------------------------------------------------------------------
# Merge into ~/.claude/settings.json
# ---------------------------------------------------------------------------

# The command paths to register.
# We pass these via shell variables to avoid jq injection.
NEW_ENTRY_COMMAND="$HOOK_DEST"
SESSION_END_COMMAND="$SESSION_END_DEST"

# Idempotency filter: does a UserPromptSubmit entry for this exact command already exist?
already_installed() {
  jq -e --arg cmd "$NEW_ENTRY_COMMAND" '
    .hooks.UserPromptSubmit? // []
    | map(.hooks // [] | map(.command) | index($cmd))
    | any(. != null)
  ' "$SETTINGS_FILE" >/dev/null 2>&1
}

# Idempotency filter: does a SessionEnd entry for this exact command already exist?
already_installed_session_end() {
  jq -e --arg cmd "$SESSION_END_COMMAND" '
    .hooks.SessionEnd? // []
    | map(.hooks // [] | map(.command) | index($cmd))
    | any(. != null)
  ' "$SETTINGS_FILE" >/dev/null 2>&1
}

if [ ! -f "$SETTINGS_FILE" ]; then
  # Create minimal settings.json from scratch with both hook entries
  echo "Settings file not found — creating: $SETTINGS_FILE"
  mkdir -p "$(dirname "$SETTINGS_FILE")"

  jq -n --arg cmd "$NEW_ENTRY_COMMAND" --arg cmd_se "$SESSION_END_COMMAND" '{
    "hooks": {
      "UserPromptSubmit": [
        {
          "matcher": "",
          "hooks": [
            { "type": "command", "command": $cmd }
          ]
        }
      ],
      "SessionEnd": [
        {
          "matcher": "",
          "hooks": [
            { "type": "command", "command": $cmd_se }
          ]
        }
      ]
    }
  }' > "$SETTINGS_FILE"

  echo "Created: $SETTINGS_FILE"

else
  # Backup before touching
  BACKUP="$SETTINGS_FILE.bak.$(date +%s)"
  cp "$SETTINGS_FILE" "$BACKUP"
  echo "Backed up settings: $BACKUP"

  # Validate the existing file is parseable JSON
  if ! jq empty "$SETTINGS_FILE" 2>/dev/null; then
    echo "ERROR: $SETTINGS_FILE is not valid JSON — aborting merge." >&2
    echo "Restore from backup: $BACKUP" >&2
    exit 1
  fi

  # --- UserPromptSubmit merge (independent of SessionEnd check) ---
  if already_installed; then
    echo "Already installed — UserPromptSubmit hook entry already present."
  else
    # Merge: append new entry to UserPromptSubmit array (create array/key if absent)
    MERGED="$(jq --arg cmd "$NEW_ENTRY_COMMAND" '
      .hooks                    //= {}
      | .hooks.UserPromptSubmit //= []
      | .hooks.UserPromptSubmit += [
          {
            "matcher": "",
            "hooks": [
              { "type": "command", "command": $cmd }
            ]
          }
        ]
    ' "$SETTINGS_FILE")"

    # Write atomically via temp file
    TMPFILE="$(mktemp "$SETTINGS_FILE.tmp.XXXXXX")"
    echo "$MERGED" > "$TMPFILE"
    mv "$TMPFILE" "$SETTINGS_FILE"

    echo "Merged UserPromptSubmit hook entry into: $SETTINGS_FILE"
  fi

  # --- SessionEnd merge (independent of UserPromptSubmit check) ---
  if already_installed_session_end; then
    echo "Already installed — SessionEnd hook entry already present."
  else
    # Merge: append new entry to SessionEnd array (create array/key if absent)
    MERGED_SE="$(jq --arg cmd "$SESSION_END_COMMAND" '
      .hooks            //= {}
      | .hooks.SessionEnd //= []
      | .hooks.SessionEnd += [
          {
            "matcher": "",
            "hooks": [
              { "type": "command", "command": $cmd }
            ]
          }
        ]
    ' "$SETTINGS_FILE")"

    # Write atomically via temp file
    TMPFILE_SE="$(mktemp "$SETTINGS_FILE.tmp.XXXXXX")"
    echo "$MERGED_SE" > "$TMPFILE_SE"
    mv "$TMPFILE_SE" "$SETTINGS_FILE"

    echo "Merged SessionEnd hook entry into: $SETTINGS_FILE"
  fi
fi

# ---------------------------------------------------------------------------
# Success summary
# ---------------------------------------------------------------------------
echo ""
echo "========================================"
echo "  claude-context-tick installed"
echo "========================================"
echo "  Hook path        : $HOOK_DEST"
echo "  Session-end hook : $SESSION_END_DEST"
echo "  Settings         : $SETTINGS_FILE"
echo "  Kill-switch      : CLAUDE_TIME_INJECT=0  (set in env to disable injection)"
echo "  GC retention     : 7 days (sweep every 24h)"
echo "  Verify with      : ls ~/.claude/state/time-inject/ after your next prompt"
echo "========================================"
echo ""

exit 0
