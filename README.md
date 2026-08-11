# TermiNap

**Terminal agents finish. Then your Mac naps.**

TermiNap is a tiny native macOS companion for terminal coding agents. It tracks every active Codex task as a battery segment and can turn off the display, put the Mac to sleep, or shut it down after the last task finishes.

[简体中文](README.zh-CN.md) · [Product state and power logic](docs/PRODUCT_STATE_LOGIC.md) · [Marketing plan](MARKETING_PLAN.md) · [Product Hunt launch kit](PRODUCT_HUNT.md)

> Development preview: the agent-to-sleep loop is implemented. Public binary releases still need battery safeguards, Developer ID signing, and Apple notarization.

## Why TermiNap

Long-running terminal agents create an awkward power-management problem: letting macOS sleep can interrupt the work, while generic keep-awake tools do not know when the final agent has finished.

TermiNap is designed around the agent lifecycle:

- One active terminal task equals one battery segment.
- Multiple Codex terminals are tracked together.
- While at least one tracked task is active, macOS stays awake but the display may turn off normally.
- A Codex permission wait is shown as paused progress, but remains unfinished and keeps the system awake.
- If a Codex process disappears without a completion event, the task becomes recoverable instead of being treated as finished.
- After every tracked task has truly finished, a cancelable five-minute countdown starts.
- A new task cancels the pending power action.
- The night-shift switch is consumed after one completed power action, so it cannot trigger again after wake or restart.
- All activity and settings stay on the Mac.

## Current features

- Tracks terminal Codex running, permission-wait, resume, and completion states through five lifecycle hooks.
- Recovers unfinished turns from live terminal Codex sessions that were already open when TermiNap launched.
- Detects tasks interrupted by a terminal or Codex process exit, suppresses the completion countdown, and offers one-click resume in a new terminal.
- Ignores Codex/ChatGPT desktop sessions without a TTY.
- Shows up to eight active tasks, with a `+N` overflow indicator.
- Uses a process-scoped macOS assertion to prevent only user-idle system sleep while agents work.
- Keeps the assertion while a process is running or waiting for permission and through the five-minute completion countdown, then rechecks task state and releases it before the selected power action.
- Releases the assertion after an abnormal process exit while retaining the interrupted session for recovery.
- Supports display sleep, system sleep, and shutdown.
- Requires an explicit confirmation before enabling shutdown.
- Installs and merges user-level hooks without removing unrelated hooks.
- Guides first-time users through Codex hook trust and detects `0/5` through `5/5` trust progress.
- Keeps its floating panel fully visible across multiple displays.

## Requirements

- macOS 13 or newer
- Apple Silicon
- Codex CLI, or a Codex executable bundled with ChatGPT/Codex for macOS
- Swift 5.9 or newer when building from source

## Build and install

```bash
swift test
./scripts/build-app.sh
./scripts/install-app.sh
open ~/Applications/TermiNap.app
```

The build script creates `.build/TermiNap.app`. The install script copies it to `~/Applications/TermiNap.app`.

The current build is ad-hoc signed for local development. Public binary releases must use a Developer ID signature and Apple notarization.

## Trust the Codex hooks

On first launch, TermiNap merges five handlers into `~/.codex/hooks.json` and preserves unrelated hooks. If a hooks file already exists, it creates `~/.codex/hooks.json.before-terminap`.

Codex requires the user to approve new hook definitions:

1. Click **Open guided Codex** in TermiNap.
2. Paste the `/hooks` command that TermiNap copied to the clipboard.
3. Review and trust the five TermiNap hooks.

TermiNap checks the trust state through the Codex app-server and switches to the battery view after all five hooks are accepted. It never edits Codex's private trust state or uses a trust-bypass flag.

## Privacy and safety

- No account is required.
- No prompts, source code, project contents, or terminal output are collected.
- Existing-session and crash recovery read only the session ID, working directory, PID, executable path, and lifecycle event fields needed to classify and resume a terminal Codex session.
- State is stored under `~/Library/Application Support/TermiNap/`.
- Power automation is off by default.
- Each enablement is one-shot and is persisted as disabled before display sleep, system sleep, or shutdown is requested.
- The wake guard uses `PreventUserIdleSystemSleep`; it does not hold a display-sleep assertion.
- The assertion belongs to the TermiNap process, so macOS removes it if the app crashes or is killed.
- Shutdown requires a second confirmation and a cancelable five-minute countdown.

For development, set `TERMINAP_DRY_RUN=1` before launching the executable. Power actions will be written to `dry-run.log` instead of being executed.

## Roadmap before a public launch

- Add AC-power-only and low-battery safeguards.
- Add launch-at-login and completion notifications.
- Add an instant-message notification when a task waits for permission.
- Ship a Developer ID signed and notarized DMG.

Closed-lid operation is deliberately out of scope until it can be implemented with a narrowly scoped, auditable privileged helper and reliable recovery behavior.

## Uninstall

1. Quit TermiNap.
2. Remove `TermiNap.app`.
3. Remove only the TermiNap command entries from `~/.codex/hooks.json`.
4. Optionally remove `~/Library/Application Support/TermiNap/`.

Do not replace the whole hooks file if it contains handlers from other tools.

## Contributing

Issues and pull requests are welcome. Run the test suite before submitting a change:

```bash
swift test
```

Please do not market an unfinished roadmap item as an existing feature.

## License

MIT. See [LICENSE](LICENSE).

TermiNap is an independent open-source project and is not affiliated with, endorsed by, or sponsored by OpenAI.
