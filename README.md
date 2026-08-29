# claudius-sculptus

Personal [Claude Code](https://code.claude.com) setup — custom status lines,
sound + desktop notifications, a system-wide `CLAUDE.md`, and a smarter `/init`
command, all wired up by a single installer.

## Contents

| File | Purpose |
|------|---------|
| `statusline-command.sh`  | Main status line. Installs to `~/.claude/statusline-command.sh`. |
| `subagent-statusline.sh` | Subagent panel row renderer. Installs to `~/.claude/subagent-statusline.sh`. |
| `settings.snippet.json`  | `statusLine` / `subagentStatusLine` keys plus the `Notification` / `Stop` hooks, merged into `~/.claude/settings.json`. |
| `media/*.mp3`            | Notification sounds. Installed into `~/.claude/sounds/`. |
| `global-CLAUDE.md`       | System-wide rules. Installs to `~/.claude/CLAUDE.md` (loaded in every session). |
| `commands/init.md`       | Custom `/init` slash command. Installs into `~/.claude/commands/`. |
| `install.sh`             | Installs all of the above. Runs from a local clone or via `curl … \| bash`. |

## Status line

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

Both scripts read the JSON that Claude Code writes to stdin. See the
[status line docs](https://code.claude.com/docs/en/statusline) for the field reference
(`.model.display_name`, `.effort.level`, `.context_window.used_percentage`, the
per-task `.tasks[]` array, etc.). Requires Claude Code v2.1.214+ for the subagent
`effort` field and `jq` on `PATH`.

## Notifications (sound + desktop)

The `Notification` and `Stop` hooks in `settings.snippet.json` fire a desktop
notification (`notify-send`) and play a sound via `ffplay`:

- **Notification** (Claude is waiting for input) → Minecraft villager "huh".
- **Stop** (a turn finished) → cartoon "eating".

`install.sh` copies the `media/*.mp3` files into `~/.claude/sounds/`. Sounds need
`ffplay` (from ffmpeg); without it the desktop notification still shows, just no
sound.

## System-wide CLAUDE.md

`global-CLAUDE.md` installs to `~/.claude/CLAUDE.md` and is loaded into every Claude
Code session on this machine. It codifies house rules: code quality, language
(English artifacts / Turkish chat), knowledge & uncertainty, documentation,
communication style, work discipline, and git conventions.

## Custom /init

`commands/init.md` installs into `~/.claude/commands/` and adds a smarter `/init`
that **extends** the built-in one (both stay available in the menu). It scans the
repo first, interviews you from what it found (improvised, not a fixed list), writes
a curated root `CLAUDE.md`, and runs routine setup — a `.claude.local` symlink to
the project's Claude data dir, `git init` if needed, `.gitignore` entries, and a
`plans/` directory.

## Install

From a local checkout:

```bash
./install.sh
```

Or straight from GitHub, without cloning first:

```bash
curl -fsSL https://raw.githubusercontent.com/kuvarti/claudius-sculptus/master/install.sh | bash
```

When run this way the script clones the repo into a temporary directory and installs
from there. Then restart Claude Code (or open a new session). To apply manually
instead, copy the `*.sh` files into `~/.claude/`, the sounds into `~/.claude/sounds/`,
`global-CLAUDE.md` to `~/.claude/CLAUDE.md`, `commands/*.md` into `~/.claude/commands/`,
and merge `settings.snippet.json` into `~/.claude/settings.json`.
