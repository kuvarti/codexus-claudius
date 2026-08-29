# Global Working Agreements

This file applies to all Codex sessions on this machine. It is installed to
`~/.codex/AGENTS.md`.

## Code Quality

- Use meaningful names, small single-responsibility functions, and clear intent.
- Avoid premature abstraction and unnecessary complexity. Apply YAGNI.
- Comments should explain intent or constraints, not narrate obvious code.

## Language

- Write code, comments, identifiers, logs, documentation, plans, commit messages,
  branch names, and file names in English unless explicitly asked otherwise.
- Converse with the user in Turkish by default unless explicitly asked otherwise.
- Technical terms may remain in English inside Turkish sentences.

## Knowledge and Uncertainty

- Never fabricate information. Check the project or authoritative documentation
  when a fact, API, or version is uncertain.
- Inspect manifests and source before assuming which libraries or commands exist.
- Prefer current supported approaches without adding unnecessary complexity.

## Project Knowledge and Documentation

- Persist durable, shareable project knowledge in the repository.
- Keep root `AGENTS.md` concise and current; put deeper material under `docs/`.
- Update documentation in the same change that makes it stale.
- Capture non-obvious decisions and constraints, not facts already obvious in code.

## Communication and Work Discipline

- Be direct and concise. Give short progress notes at meaningful checkpoints.
- Verify before claiming a change works. Report skipped or failed checks plainly.
- Ask before actions that require new authority or materially expand the task.

## Git

- Never commit, push, tag, or change a remote unless the user explicitly asks.
- Use English Conventional Commit messages with a useful body when committing.
- Do not add an AI co-author or generated-by footer unless the user explicitly asks.
