# claudius-sculptus

Claude Code status line configuration — backup & installer.

Two custom status lines for [Claude Code](https://code.claude.com), derived from the
user's bash `PS1`, plus a per-subagent row renderer that shows each subagent's model
and reasoning effort.

## Contents

| File | Purpose |
|------|---------|
| `statusline-command.sh`  | Main status line. Installs to `~/.claude/statusline-command.sh`. |
| `subagent-statusline.sh` | Subagent panel row renderer. Installs to `~/.claude/subagent-statusline.sh`. |
| `settings.snippet.json`  | The `statusLine` / `subagentStatusLine` keys to merge into `~/.claude/settings.json`. |
| `install.sh`             | Copies the scripts and merges the snippet into `settings.json`. |

## What it looks like

**Main status line** (two lines; top line only when the session has a name):

```
statusline-work
[kuvarti@cachyos-server gittest]   main  ▓▓▓▓░░░░ 42% (84K Tokens) ctx  Opus 4.8 (high)
```

- `[user@host dir]` — from the bash `PS1` `[\u@\h \W]`
- git branch with a `` icon and a `*` dirty flag (yellow when dirty, green when clean)
- context-window usage bar + percentage (green < 50%, yellow 50–79%, red ≥ 80%), with the used token count in parentheses (`total_input_tokens`, compacted to `84K`)
- model display name and current reasoning effort

**Subagent rows** (`name  Model ·effort  description  tokens`):

```
Report GPU info   Opus 4.8 ·high   12.3ktok
security-reviewer Haiku 4.5 ·low   reviewing the diff   800tok
```

- title falls back `.name → .label → .description → .type` (`.name` is `null` for ad-hoc agents)
- model id (`claude-opus-4-8`) is prettified to `Opus 4.8`; date suffixes are stripped
- effort is always shown: the task's own effort, else the live session effort, else `effortLevel` from `settings.json`
- description is shown only when it differs from the title; token count is compacted (`12.3ktok`)

## Data source

Both scripts read the JSON that Claude Code writes to stdin. See the
[status line docs](https://code.claude.com/docs/en/statusline) for the field reference
(`.model.display_name`, `.effort.level`, `.context_window.used_percentage`, the
per-task `.tasks[]` array, etc.). Requires Claude Code v2.1.214+ for the subagent
`effort` field and `jq` on `PATH`.

## Install

```bash
./install.sh
```

Then restart Claude Code (or open a new session). To apply manually instead, copy the
two `*.sh` files into `~/.claude/` and merge `settings.snippet.json` into
`~/.claude/settings.json`.
