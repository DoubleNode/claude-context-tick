# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
