# claude-context-tick

![CI](https://github.com/DoubleNode/claude-context-tick/actions/workflows/ci.yml/badge.svg)
![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)
![macOS](https://img.shields.io/badge/platform-macOS-lightgrey.svg)
![Linux](https://img.shields.io/badge/platform-Linux-lightgrey.svg)

A Claude Code UserPromptSubmit hook that injects wall-clock time into conversation context at meaningful boundaries.

## Why

Claude has no built-in concept of wall-clock time mid-conversation. The model's "today's date" comes from the system prompt at session start, but after that, subjective time inside the conversation drifts. Agents lose track of date rollovers, scheduled wake-ups, quarter-hourly pacing, and timezone shifts. This hook nudges Claude with a tiny ground-truth timestamp only when the answer to "what time is it actually" has materially changed — minimizing token cost while keeping the agent grounded.

## What It Does

The hook injects a single-line context message `<context-tick>YYYY-MM-DD · HH:MM TZ</context-tick>` into the conversation **only** on state transitions that matter:

- **First run of a session** — establishes baseline time
- **Date rollover** — midnight boundary crossed
- **Quarter-hour tick** — minute boundary hits 00, 15, 30, or 45
- **Timezone shift** — DST transition or laptop traveling

State is tracked per-session in `~/.claude/state/time-inject/` with atomic writes (`mktemp` + `mv`) preventing partial state corruption on abnormal exits.

## Install

### One-Line Install

```bash
curl -fsSL https://raw.githubusercontent.com/DoubleNode/claude-context-tick/main/scripts/install.sh | bash
```

**Security note:** Always review scripts before piping to `bash`. The script simply merges the hook entry into `~/.claude/settings.json`.

### Manual Install

```bash
git clone https://github.com/DoubleNode/claude-context-tick.git
cd claude-context-tick
bash scripts/install.sh
```

### Hand-Merge settings.json

If you prefer to merge manually, copy the `hooks` entry from `settings.example.json` into your `~/.claude/settings.json`:

```json
{
  "hooks": {
    "userPromptSubmit": {
      "path": "/path/to/claude-context-tick/hooks/inject-time-context.sh",
      "enabled": true
    }
  }
}
```

Ensure the `hooks` key exists; if not, create it at the top level.

## Configuration

Environment variable to control behavior:

| Variable | Default | Effect |
|----------|---------|--------|
| `CLAUDE_TIME_INJECT` | `1` | Set to `0` to disable the hook entirely (all injections suppressed) |

Example: `CLAUDE_TIME_INJECT=0 claude` launches a session with no time injections.

## How It Decides Whether to Inject (State-Tracking Explainer)

On each prompt submission, the hook:

1. **Checks the kill-switch** (`CLAUDE_TIME_INJECT=0`). If enabled, exits silently with no injection.
2. **Reads the current session_id** from stdin (Claude Code UserPromptSubmit metadata). Sanitizes it via positive whitelist `[A-Za-z0-9._-]` so untrusted input cannot escape the state directory.
3. **Looks up the session's prior state** in `~/.claude/state/time-inject/{SESSION_ID}.json`. If the file doesn't exist, this is the first run.
4. **Evaluates four conditions in order:**
   - First run? Inject full timestamp.
   - Timezone changed (DST or `readlink /etc/localtime` differs)? Inject.
   - Date changed (midnight crossed)? Inject.
   - Quarter-hour boundary (minute in [00, 15, 30, 45])? Inject.
5. **If any condition fires**, write new state atomically (via `mktemp`, then `mv`) and emit the injection JSON to stdout per the UserPromptSubmit protocol.

The state file format is simple JSON:

```json
{
  "date": "2026-05-06",
  "qh": "2026-05-06T14:30",
  "iana": "America/Los_Angeles",
  "tz": "PDT",
  "reason": "date-rollover"
}
```

The `reason` field documents why the injection fired (useful for debugging).

## Uninstall

```bash
bash scripts/uninstall.sh
```

This removes the hook entry from `~/.claude/settings.json`. The state directory `~/.claude/state/time-inject/` is left in place (can be manually removed if desired).

## Troubleshooting

### "I don't see any `<context-tick>` lines in my conversation"

The first prompt of any session should always fire an injection. Check `~/.claude/state/time-inject/` — you should see one `.json` file per session ID. If it's empty:

- Verify `~/.claude/settings.json` has the hook entry under `hooks.userPromptSubmit`.
- Confirm the `path` points to your `inject-time-context.sh` script (not a stale path).
- Try the one-line install again to refresh the config.

### "Hook fires but injection is missing from the conversation"

The hook ran but the state directory could not be written. This can happen if:

- `~/.claude/state/` or `~/.claude/state/time-inject/` is read-only.
- Disk is full.

The hook silently exits on write failures (by design — it is best-effort and should not spam the Claude Code UI with errors). Resolve the write issue, then start a new Claude Code session.

### "Suspicious characters in my session_id warning"

Not a warning. D3 sanitization silently strips any character outside `[A-Za-z0-9._-]` from the session_id before using it as a filename. This is intentional and safe.

## Security

The hook:

- **Reads only from stdin** (session metadata from Claude Code).
- **Writes only to `~/.claude/state/time-inject/`** (local state files, JSON format).
- **Never touches the network** or makes external API calls.
- **Sanitizes session_id** via positive whitelist before using it as a filename, preventing directory traversal attacks (e.g., `../etc/passwd` injection).
- **Respects the kill-switch** (`CLAUDE_TIME_INJECT=0`) before any I/O.

State files contain only timestamps and timezone metadata — no sensitive information.

## Compatibility

**Bash:** 4.0+. macOS ships with bash 3.2 by default; this script uses `[[ ... ]]` and string comparisons compatible with 3.2. If you install bash 5+ via Homebrew, the shebang `#!/usr/bin/env bash` will pick it up automatically.

**Python:** 3.6+ required (already a Claude Code dependency). Used for robust JSON parsing and session_id sanitization.

**Platforms:** macOS (primary), Linux (Ubuntu, Debian tested; other distributions may vary). The hook tolerates non-symlink `/etc/localtime` on systems where readlink fails.

## License

MIT. See [LICENSE](LICENSE) for details.

## Contributing

Issues and pull requests welcome at [https://github.com/DoubleNode/claude-context-tick/issues](https://github.com/DoubleNode/claude-context-tick/issues).

Tests live in `tests/`; contributions should include test cases. CI runs on macOS and Ubuntu via GitHub Actions.
