#!/usr/bin/env bash
# uninstall.sh — claude-context-tick uninstaller
#
# Removes the inject-time-context.sh hook entry from ~/.claude/settings.json
# and optionally removes the installed hook script and state directory.
#
# Usage:
#   bash scripts/uninstall.sh          # interactive prompts
#   bash scripts/uninstall.sh --yes    # remove everything without prompting

set -euo pipefail

YES_FLAG=0
for arg in "$@"; do
  if [ "$arg" = "--yes" ] || [ "$arg" = "-y" ]; then
    YES_FLAG=1
  fi
done

SETTINGS_FILE="$HOME/.claude/settings.json"
HOOK_SCRIPT="$HOME/.claude/hooks/inject-time-context.sh"
STATE_DIR="$HOME/.claude/state/time-inject"

HOOK_MATCH_PATTERN="inject-time-context.sh"

# ---------------------------------------------------------------------------
# Pre-flight
# ---------------------------------------------------------------------------
if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq is required but not found on PATH." >&2
  exit 1
fi

if [ ! -f "$SETTINGS_FILE" ]; then
  echo "Settings file not found: $SETTINGS_FILE"
  echo "Nothing to do for settings."
  SETTINGS_MODIFIED=0
else
  # Validate JSON
  if ! jq empty "$SETTINGS_FILE" 2>/dev/null; then
    echo "ERROR: $SETTINGS_FILE is not valid JSON — aborting." >&2
    exit 1
  fi
  SETTINGS_MODIFIED=1
fi

# ---------------------------------------------------------------------------
# Backup + remove hook entries from settings.json
# ---------------------------------------------------------------------------
if [ "$SETTINGS_MODIFIED" -eq 1 ]; then
  BACKUP="$SETTINGS_FILE.bak.$(date +%s)"
  cp "$SETTINGS_FILE" "$BACKUP"
  echo "Backed up settings: $BACKUP"

  # Remove any UserPromptSubmit entry whose hooks[].command ends with our hook name.
  # After removal:
  #   - if UserPromptSubmit array is empty  → drop the key
  #   - if hooks object is empty            → drop the key
  PATCHED="$(jq --arg pat "$HOOK_MATCH_PATTERN" '
    if .hooks.UserPromptSubmit? then
      .hooks.UserPromptSubmit |= map(
        .hooks |= map(select(.command | endswith($pat) | not))
        | select(.hooks | length > 0)
      )
      | if (.hooks.UserPromptSubmit | length) == 0 then
          del(.hooks.UserPromptSubmit)
        else . end
      | if (.hooks | length) == 0 then
          del(.hooks)
        else . end
    else .
    end
  ' "$SETTINGS_FILE")"

  # Write atomically
  TMPFILE="$(mktemp "$SETTINGS_FILE.tmp.XXXXXX")"
  echo "$PATCHED" > "$TMPFILE"
  mv "$TMPFILE" "$SETTINGS_FILE"

  echo "Removed hook entries from: $SETTINGS_FILE"
fi

# ---------------------------------------------------------------------------
# Optionally remove installed hook script
# ---------------------------------------------------------------------------
remove_hook_script=0

if [ -f "$HOOK_SCRIPT" ]; then
  if [ "$YES_FLAG" -eq 1 ]; then
    remove_hook_script=1
  else
    read -r -p "Remove installed hook script ($HOOK_SCRIPT)? [y/N] " reply
    case "$reply" in
      [Yy]*) remove_hook_script=1 ;;
      *) echo "Keeping hook script." ;;
    esac
  fi

  if [ "$remove_hook_script" -eq 1 ]; then
    rm -f "$HOOK_SCRIPT"
    echo "Removed: $HOOK_SCRIPT"
  fi
else
  echo "Hook script not found at $HOOK_SCRIPT — skipping."
fi

# ---------------------------------------------------------------------------
# Optionally remove state directory
# ---------------------------------------------------------------------------
remove_state=0

if [ -d "$STATE_DIR" ]; then
  if [ "$YES_FLAG" -eq 1 ]; then
    remove_state=1
  else
    STATE_COUNT="$(find "$STATE_DIR" -type f | wc -l | tr -d ' ')"
    read -r -p "Remove state directory ($STATE_DIR, $STATE_COUNT file(s))? [y/N] " reply
    case "$reply" in
      [Yy]*) remove_state=1 ;;
      *) echo "Keeping state directory." ;;
    esac
  fi

  if [ "$remove_state" -eq 1 ]; then
    rm -rf "$STATE_DIR"
    echo "Removed: $STATE_DIR"
  fi
else
  echo "State directory not found at $STATE_DIR — skipping."
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "========================================"
echo "  claude-context-tick uninstalled"
echo "========================================"
[ "$SETTINGS_MODIFIED" -eq 1 ] && echo "  Settings  : hook entries removed"
[ -n "${BACKUP:-}" ]           && echo "  Backup    : $BACKUP"
[ "$remove_hook_script" -eq 1 ] && echo "  Hook      : removed" || echo "  Hook      : kept (or not found)"
[ "$remove_state" -eq 1 ]      && echo "  State dir : removed" || echo "  State dir : kept (or not found)"
echo "========================================"
echo ""

exit 0
