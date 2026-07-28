# Changelog

All notable changes to TermiNap will be documented in this file.

## 0.2.0 — Unreleased

### Added

- Process-scoped `PreventUserIdleSystemSleep` assertion while tracked agents are active.
- Wake protection through the completion countdown without blocking normal display sleep.
- In-app wake-guard status and clearer night-shift automation language.
- Fail-safe assertion cleanup on disabled automation, state errors, stale sessions, and process exit.

### Verified

- Unit coverage for wake policy, idempotent acquisition, error handling, and deinitialization cleanup.
- Live macOS `pmset -g assertions` verification confirms display sleep remains unblocked and the TermiNap assertion disappears after process termination.

## 0.1.0 — 2026-07-29

### Added

- Native macOS floating battery panel.
- Multi-terminal Codex task tracking through lifecycle hooks.
- Display sleep, system sleep, and shutdown actions after the final task.
- Cancelable 15-second completion countdown.
- First-run hook installation and `0/3` through `3/3` trust onboarding.
- Multi-display window placement and off-screen recovery.
- English and Simplified Chinese documentation.

### Known limitations

- Only terminal Codex is supported.
- Public binaries are not yet Developer ID signed or notarized.
- Closed-lid operation is not supported.
