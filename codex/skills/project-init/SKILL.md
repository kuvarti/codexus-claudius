---
name: project-init
description: Inspect a repository, interview the user about meaningful gaps, and create or improve its root AGENTS.md plus minimal local setup. Use when the user asks to initialize Codex project guidance or explicitly invokes $project-init; do not use for ordinary feature work.
---

# Project Init

Initialize durable Codex guidance for the current repository. Do not commit.

## Inspect first

Survey the repository before asking questions:

- Identify languages, frameworks, package manager, and build, lint, and test commands.
- Find entry points, architecture boundaries, existing documentation, and git state.
- Read any existing `AGENTS.md` files and distinguish confirmed facts from inference.

## Resolve meaningful gaps

Tell the user what the repository appears to be, then ask one question at a time
only where the answer would materially improve project guidance. Confirm purpose,
scope boundaries, and non-obvious conventions that cannot be learned from the repo.
Drop blank, vague, or unknown answers instead of inventing content.

## Write AGENTS.md

Create or carefully update the root `AGENTS.md` in English. Keep it concise and
specific to the repository. Include only durable facts, useful commands,
non-obvious constraints, and conventions that affect future work. Do not restate
the source tree or pad empty sections.

## Optional routine setup

Present the following missing setup as one batch and get confirmation before
performing it:

- Initialize git only when the directory is not already a repository.
- Ensure a root `.gitignore` exists and add `/plans` only when absent.
- Create `plans/` only when absent.

Do not configure MCP servers. Finish with a short summary of what was written and
which setup items ran or were already present.
