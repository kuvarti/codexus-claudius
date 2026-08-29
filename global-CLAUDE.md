# System-wide Rules

This file applies to all Claude Code sessions on this machine.
It is installed to `~/.claude/CLAUDE.md`.

## Code Quality
- Follow **Clean Code**: meaningful names, small single-responsibility functions, no needless repetition, clear intent.
- No premature abstraction or over-engineering. Do not add an abstraction before a real need exists (YAGNI).
- Comments explain the **why** (intent/reason), not the **what**. Well-named code should not need comments.

## Language
- **All written artifacts are in English by default**: code, comments, identifiers, string literals, log messages, documentation and markdown files (README, CLAUDE.md, docs), plans, commit messages, branch names, and file names. Use another language only when explicitly asked.
- **Conversation with the user is in Turkish by default.** Use another language only when explicitly asked.
- Technical terms and tool names may stay in English inside Turkish sentences (e.g. "branch", "merge conflict", "dependency injection") — Turkish sentence structure, English terms.

## Knowledge and Uncertainty
- Never **fabricate** information. Say "I don't know" or "I need to check" when unsure.
- If you do not remember a library or API, first check the project's manifest (`package.json` / `pyproject.toml` / `Cargo.toml`) or grep the source. Do not assume.
- **Search the web when you do not know something.** This is a fast-moving ecosystem where docs and versions change often — use WebSearch / WebFetch without hesitation.
- Overall aim: **modern and fast** — prefer current best practices over deprecated approaches, without adding unnecessary complexity.

## Project Knowledge and Documentation
- **Persist durable project knowledge in the repo, not only in local memory.** Local memory (`~/.claude/.../memory/`) is personal, machine-local, and point-in-time — not version-controlled, not shared, lost if `.claude` is wiped. The repo is the shared, durable source of truth. When you learn something durable (architecture, a subsystem's real behavior, a non-obvious gotcha, a design decision), record it in-repo as part of the same work.
- **Two tiers, by altitude:**
  - **`CLAUDE.md`** (repo root) — concise, curated, *current* high-level truth a new engineer or session needs first. It is loaded every session, so keep it tight and accurate and prune stale claims.
  - **`docs/`** — maintained as an **Obsidian vault**: atomic, curated Markdown notes cross-linked with `[[wiki-links]]`, not a raw note dump. Holds the deeper detail that would bloat CLAUDE.md (subsystem deep-dives, design decisions, known gaps), read on demand and linked from CLAUDE.md.
- **Treat docs like code:** update them in the same change that makes them stale — a wrong doc is worse than no doc. Don't duplicate what the code or git history already records; capture the *why* and the non-obvious.
- **Local memory still has a role:** personal preferences, feedback, cross-project notes, and anything not appropriate to commit. When a memory turns out durable and shareable, promote it into the repo.

## Communication Style
- Responses are **direct and concise**. No filler intros, no upfront summary of what you are about to do, no closing recap.
- Do not pad with a step-by-step roadmap of what you are *about* to do; do the work and give short progress notes at meaningful decision points — while still pausing to plan and check in before non-trivial or hard-to-reverse changes.

## Work and Approval Discipline
- **Verify before claiming done.** Do not say something works, passes, or is fixed without running the check and seeing the output. If a test fails or a step was skipped, say so plainly.
- **Keep plan files under `./plans`.** When a plan is prepared (e.g. the kind designed in plan mode), save it as a file in a `./plans` folder at the project root, creating `./plans` if it does not exist. When you start implementing the plan, append a **progress log** to the end of that same file — the concrete things you actually did, each stamped with the date and time.

## Git and Commits
- **Never `git commit`, `git push`, `git tag`, or run any command that affects the remote unless the user explicitly asks.** No automatic commits or pushes.
- **Only an explicit commit/push request grants permission.** Indirect instructions do not authorize a commit — "finish the work", "wrap it up", "make it done", "get it working" mean *do the work*, not commit it. When in doubt, do the work and stop before committing.
- **When the user does request a commit or push:**
  - Commit messages are detailed and written entirely in English.
  - Use the **Conventional Commits** format (`feat:`, `fix:`, `chore:`, `refactor:`, `docs:`, `test:`).
  - The message covers both **what** was done (subject line) and **why** it was done (body).
  - Never add Claude Code (or any AI assistant) as a co-author: no `Co-Authored-By: Claude ...` trailer, no "Generated with Claude Code" footer.
- **Exception — plan implementation:** while implementing a plan you may commit at the end of each phase without asking, unless the user says otherwise. Local commits only; this never authorizes `git push`.
