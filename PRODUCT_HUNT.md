# TermiNap Product Hunt launch kit

Do not submit TermiNap to Product Hunt until every P0 item in [MARKETING_PLAN.md](MARKETING_PLAN.md) is complete. In particular, the product must keep the system awake while agents work, fail safely, and ship as a signed and notarized download.

## Listing

**Name**

TermiNap

**Tagline**

Let terminal agents finish before your Mac takes a nap.

**Short description**

TermiNap is a native macOS power companion for terminal coding agents. It keeps the system awake while Codex works, shows every active task as a battery segment, and lets the Mac sleep after the final agent finishes.

**Topics**

- Developer Tools
- Artificial Intelligence
- Mac
- Open Source
- Productivity

**Primary call to action**

Download for macOS

**Secondary call to action**

View source on GitHub

## Gallery sequence

1. Hero: three Codex terminals and three active battery segments.
2. Lifecycle: agents working, display off, system awake.
3. Completion: the last segment reaches zero and starts the countdown.
4. Choice: display sleep, system sleep, or shutdown.
5. Trust: local-only design, visible hooks, no account required.

Every screenshot and video must reflect behavior present in the published build.

## Maker comment

Hi Product Hunt — I built TermiNap after repeatedly starting long Codex tasks before stepping away from my Mac.

Generic keep-awake tools solve only half of the problem: they can keep a Mac running, but they do not know when the final coding agent has finished. TermiNap follows the actual terminal-agent lifecycle, represents every active task as a battery segment, and releases the Mac to sleep after the last one is done.

It is a small native Swift app, runs locally, needs no account, and does not read prompts or source code. The Codex hook integration is visible and still requires the user to approve it; TermiNap does not bypass that security boundary.

The first release focuses narrowly on terminal Codex for accuracy. I would especially value feedback on multi-terminal detection, power safeguards, and the first-run trust flow.

## Launch video

Create one 12-second silent loop:

| Time | Visual | Caption |
| --- | --- | --- |
| 0–2 s | Three long Codex tasks start at 23:48 | Three agents start the night shift |
| 2–4 s | Three battery segments light up | One task, one segment |
| 4–7 s | The display turns off while tasks continue | Display off. Agents still working. |
| 7–10 s | Segments fall from three to zero | The final agent finishes |
| 10–12 s | A cancelable sleep countdown appears | Then your Mac naps |

## Launch-day responses

### Why not use `caffeinate`?

`caffeinate` is excellent at holding a power assertion, but it does not know when every coding-agent task has ended. TermiNap joins task lifecycle detection with power cleanup.

### Does the display stay on?

No. The intended behavior is to prevent idle system sleep while allowing normal display sleep.

### Does it work with the lid closed?

Not in the first public release. Closed-lid operation requires a more privileged mechanism, and TermiNap will not promise it before that mechanism is narrowly scoped, auditable, and recoverable.

### Does it read my code or prompts?

No. TermiNap receives lifecycle metadata from local Codex hooks and does not collect prompts, source code, project contents, or terminal output.

### Is it affiliated with OpenAI?

No. TermiNap is an independent open-source project.

## Launch rules

- Post from the maker's personal Product Hunt account.
- Ask the community to visit, try, and comment; never directly ask for upvotes.
- Do not exchange rewards, access, or discounts for votes.
- Respond to technical questions with exact current behavior and known limits.
- Treat launch day as the start of feedback collection, not the finish line.

Refer to the [official Product Hunt launch guide](https://www.producthunt.com/launch) and [sharing rules](https://www.producthunt.com/launch/sharing-your-launch) before scheduling the launch.
