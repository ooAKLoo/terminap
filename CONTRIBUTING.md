# Contributing to TermiNap

Thank you for helping improve TermiNap.

## Before opening an issue

- Search existing issues first.
- State the macOS version, Mac model, and Codex installation type.
- Describe the expected and observed power behavior.
- Remove project paths, prompts, source code, and terminal output that should not be public.

Security-sensitive reports should follow [SECURITY.md](SECURITY.md).

## Development

TermiNap requires macOS 13 or newer and Swift 5.9 or newer.

```bash
swift test
./scripts/build-app.sh
```

Use dry-run mode when changing power behavior:

```bash
TERMINAP_DRY_RUN=1 .build/TermiNap.app/Contents/MacOS/TermiNap
```

Dry-run mode records requested actions under `~/Library/Application Support/TermiNap/` instead of executing them.

## Pull requests

- Keep each pull request focused on one behavior.
- Add tests for state transitions and safety boundaries.
- Preserve unrelated hooks in `~/.codex/hooks.json`.
- Do not bypass Codex hook trust.
- Do not upload prompts, code, project paths, or terminal output.
- Document unfinished behavior as a roadmap item, not an existing feature.

By contributing, you agree that your contribution is licensed under the MIT License.
