# Changelog

All notable changes to TermiNap will be documented in this file.

## 0.2.0 — Unreleased

### Added

- Process-scoped `PreventUserIdleSystemSleep` assertion while tracked agents are active.
- Wake protection through the completion countdown without blocking normal display sleep.
- In-app wake-guard status and clearer night-shift automation language.
- Fail-safe assertion cleanup on disabled automation, state errors, stale sessions, and process exit.
- Explicit running and waiting-for-permission task states.
- Five-event Codex lifecycle coverage, including `PermissionRequest` and `PostToolUse`.
- Product state and power-decision reference documentation.

### Fixed

- Make night-shift automation one-shot and disable it before executing a power action, preventing an unintended second trigger after wake or restart.
- Exclude Codex subagent rollout files from terminal task recovery to prevent duplicate active-task counts.
- Recover unfinished turns from terminal Codex sessions that were already open when TermiNap launched.
- Reliably collapse the floating panel after the pointer leaves while its frame is animating.
- Restore the floating panel to its previous external display and relative position after display topology changes.
- Expand upward near the screen's bottom edge while keeping the battery meter fixed and revealing content from bottom to top.
- Treat tasks blocked on user permission as paused progress instead of keeping the Mac awake indefinitely.
- Restore task tracking after an approved tool returns.
- Migrate the completion grace period from 15 to 30 seconds.
- Keep a live Codex process tracked beyond the 24-hour stale-state fallback.

### Verified

- Unit coverage for existing-session recovery, wake policy, permission pause/resume, settings migration, hook installation, idempotent acquisition, error handling, and deinitialization cleanup.
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
