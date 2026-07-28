# Security policy

TermiNap edits Codex hook configuration and can request macOS power actions. Treat failures in either area as security-sensitive.

## Reporting a vulnerability

Do not open a public issue for a vulnerability that could:

- execute an unexpected command through hook configuration;
- bypass Codex hook trust;
- expose prompts, code, project paths, or terminal output;
- trigger sleep or shutdown without the configured confirmation flow;
- leave the Mac in a persistent keep-awake state.

Send a private report through GitHub Security Advisories after the repository is published. Include reproduction steps, affected versions, and the least sensitive diagnostic information needed to reproduce the issue.

## Supported versions

TermiNap is currently an early alpha. Only the latest commit on `main` is supported until the first stable release.

## Safety boundaries

- TermiNap must preserve unrelated Codex hooks.
- Hook trust must remain a user-controlled Codex decision.
- Power automation must remain off by default.
- Shutdown must require explicit confirmation and a cancelable countdown.
- Future keep-awake behavior must fail open: if TermiNap exits or loses valid task state, macOS must be allowed to sleep normally.
