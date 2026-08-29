---
description: "A smarter /init by @Kuvarti — scans first, then asks, for a better CLAUDE.md"
---

You are running this machine's custom `/init`. Work through the sections in order, coordinating with the user in a single pass. This **extends** the standard init (scan the codebase, produce a root `CLAUDE.md`) — keep that, and add to it.

## 1. Scan the repo first and form your own read

Before asking the user anything, survey the project yourself:

- Languages, framework(s), package manager; build / lint / test commands (from manifests, config, and scripts).
- Directory structure, entry points, and the apparent architecture.
- Existing docs (README, `docs/`), the git state (is it a repo? default branch?), and any existing `CLAUDE.md`.

Form concrete inferences about what the project **is** and how it is organized, and explicitly note what you are unsure about or cannot tell from the code alone.

## 2. Interview the user, driven by what you found

Ask the questions your scan actually raised — confirm your inferences, resolve what the code could not tell you, and fill the gaps. Do **not** read from a fixed list: improvise follow-ups as the answers warrant, and don't hesitate to ask something specific to this repo. Ask one question at a time and wait for each answer. At minimum, cover:

- **Purpose** — state your inference ("this looks like X") and let the user confirm or correct it.
- **Scope and boundaries** — what is in, and what is deliberately out.
- **Whatever the scan left ambiguous** — conventions, constraints, non-obvious tooling, intended audience.

**Quality guard — do not pollute the CLAUDE.md.** If an answer is blank, "skip", "I don't know", or too vague to be actionable, drop it. Never invent content to fill a section, and never write a section that has no clear, specific input. A short, accurate CLAUDE.md beats a padded one.

## 3. Write the project CLAUDE.md

Merge the scan findings with the confirmed interview answers into a concise, curated root `CLAUDE.md` — the standard init deliverable, sharpened by the interview. Write in English (per the system-wide rules). Keep it tight — no filler, and don't restate what the code already makes obvious.

## 4. Routine setup (confirm the batch with the user, then do it in one pass)

Create only what is missing, report what you did, and commit nothing.

- **Data link:** if `./.claude.local` does not exist, create it as a symlink to this project's Claude data directory — `~/.claude/projects/<name>`, where `<name>` is the absolute working-directory path with every `/` replaced by `-` (e.g. `/home/u/Projects/x` → `-home-u-Projects-x`). Verify the target exists before linking; if it does not, find the right one under `~/.claude/projects/`.
- **Git:** if this is not a git repository, run `git init`. Ensure a `.gitignore` exists at the repo root; add `/.claude.local` and `/plans` if they are not already present.
- **Plans dir:** if `./plans` does not exist, create it.

MCP setup is intentionally deferred — do not configure MCP servers here.

## Finish

Give a short summary: what went into `CLAUDE.md`, and which setup steps ran vs. were already in place.
