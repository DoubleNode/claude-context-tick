# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `scripts/generate-social-preview.py` — Pillow-based generator for the GitHub social preview / Open Graph card. Re-runnable; portable font fallback chain (JetBrains Mono → SF Mono → Menlo → DejaVu).
- `assets/social-preview.png` — 1280×640 social preview card. Uploaded to repo Settings → Social preview to replace the default grey link unfurl.

## [0.2.0] - 2026-05-06

### Added

- Lazy garbage collection of session state files in `inject-time-context.sh`:
  - Rate-limited via `${STATE_DIR}/.gc-sweep` marker (one sweep per 24h max).
  - Prunes session state files with mtime older than 7 days.
  - Liveness signal: `touch` of the active state file on every prompt prevents quiet long-running sessions from being expired.
  - Fully silent — failures never propagate to Claude Code stderr.
- New `hooks/session-end.sh` SessionEnd hook for prompt, precise per-session cleanup. Deletes only the ending session's state file.
- `scripts/install.sh` now registers both `UserPromptSubmit` and `SessionEnd` hooks. Per-event idempotency.
- `scripts/uninstall.sh` removes both hook entries and both installed scripts.
- `settings.example.json` shows both hook registrations.
- Test coverage: `tests/test_gc_sweep.sh` (4 scenarios), `tests/test_session_end.sh` (3 scenarios). 9/9 pass on macOS + Ubuntu.

### Changed

- `tests/lib.sh` — added `run_session_end` helper.

## [0.1.0] - 2026-05-06

### Added

- Initial public release.
- `inject-time-context.sh` UserPromptSubmit hook with four-trigger injection mechanism:
  - First run of session
  - Date rollover (midnight boundary)
  - Quarter-hour tick (minute boundary at 00, 15, 30, 45)
  - Timezone shift (DST or IANA zone change)
- `CLAUDE_TIME_INJECT=0` kill-switch environment variable for disabling injection.
- Per-session state tracking via `~/.claude/state/time-inject/{SESSION_ID}.json` with positive-whitelist sanitization of session_id filenames.
- Atomic state write pattern (mktemp + mv) to prevent corruption on abnormal exits.
- `install.sh` for safe `~/.claude/settings.json` hook registration.
- `uninstall.sh` for clean removal of hook entry from settings.
- Cross-platform test suite (macOS and Ubuntu via GitHub Actions).
- Comprehensive README with problem statement, install options, configuration, troubleshooting, and security notes.
