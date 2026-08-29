# claudius-sculptus

Personal terminal enhancements for [Claude Code](https://code.claude.com) and
[OpenAI Codex CLI](https://learn.chatgpt.com/docs/codex/cli). Each CLI has its
own installer and uninstaller; there is no provider-selection wrapper.

## Repository layout

```text
.
├── install-claude.sh
├── uninstall-claude.sh
├── install-codex.sh
├── uninstall-codex.sh
├── claude/
│   ├── global-CLAUDE.md
│   ├── settings.snippet.json
│   ├── statusline-command.sh
│   ├── subagent-statusline.sh
│   └── commands/init.md
├── codex/
│   ├── global-AGENTS.md
│   ├── config.snippet.toml
│   ├── config_editor.py
│   ├── notify.sh
│   └── skills/project-init/SKILL.md
├── shared/
│   ├── lib/
│   └── media/
└── tests/
    ├── sandbox-common.sh
    ├── test-claude-sandbox.sh
    └── test-codex-sandbox.sh
```

## Requirements

Both installers require Bash, `jq`, and `sha256sum`. A remote `curl | bash`
install also requires `git` because the entry point clones the repository into a
temporary directory before installing payload files.

Codex configuration additionally requires Python 3.11+ (`tomllib`). Desktop
alerts use `notify-send`; sounds use `ffplay` from FFmpeg. Missing notification
programs produce warnings but do not block the rest of the installation.

## Claude Code

The Claude Code package provides:

- A two-line main status renderer showing session, user/host, directory, git
  branch, context usage, model, and reasoning effort.
- A subagent row renderer showing agent name, model, effort, description, and
  token usage.
- Optional desktop notifications and sounds for input requests and completed
  turns.
- An optional global `~/.claude/CLAUDE.md`.
- An optional custom `/init` command under `~/.claude/commands/`.

### Install Claude Code enhancements

From a local checkout:

```bash
./install-claude.sh
```

Directly from GitHub:

```bash
curl -fsSL https://raw.githubusercontent.com/kuvarti/claudius-sculptus/master/install-claude.sh | bash
```

The status renderers are always installed. The installer asks whether to install
the global `CLAUDE.md`, notification enhancements, and custom `/init` command.
Enter accepts the default (`yes`). Without a controlling terminal, defaults are
used automatically.

Managed state and backups live under:

```text
~/.claude/.claudius-sculptus/
```

### Uninstall Claude Code enhancements

```bash
./uninstall-claude.sh
```

Or:

```bash
curl -fsSL https://raw.githubusercontent.com/kuvarti/claudius-sculptus/master/uninstall-claude.sh | bash
```

The uninstaller asks which components to remove and requires final confirmation.
It restores files replaced during install, preserves unrelated settings and
hooks, and leaves user-modified managed files untouched with a warning.

## Codex CLI

The Codex package uses Codex-native extension points:

- `tui.status_line` configures the native footer with model/reasoning, remaining
  context, git branch, and current directory.
- `notify` invokes the installed wrapper with Codex's JSON payload. The wrapper
  shows a desktop alert and plays the shared completion or approval sound.
- `tui.notifications` enables native terminal notifications when the terminal is
  unfocused.
- An optional global `~/.codex/AGENTS.md` supplies reusable working agreements.
- An optional `$project-init` skill is installed to
  `~/.agents/skills/project-init/SKILL.md`.

These locations and settings follow the official OpenAI documentation for
[Codex configuration](https://learn.chatgpt.com/docs/config-file/config-reference),
[AGENTS.md](https://learn.chatgpt.com/docs/agent-configuration/agents-md), and
[skills](https://learn.chatgpt.com/docs/build-skills).

### Install Codex enhancements

From a local checkout:

```bash
./install-codex.sh
```

Directly from GitHub:

```bash
curl -fsSL https://raw.githubusercontent.com/kuvarti/claudius-sculptus/master/install-codex.sh | bash
```

The installer independently asks whether to configure the native status line,
enhance notifications, install the global `AGENTS.md`, and install the
`$project-init` skill. Enter accepts the default (`yes`).

The TOML editor validates `config.toml` before and after every change and edits
only these owned keys:

```text
notify
tui.notifications
tui.notification_condition
tui.status_line
```

Managed files, original values, checksums, and backups are recorded under:

```text
~/.codex/.claudius-sculptus/
```

### Uninstall Codex enhancements

```bash
./uninstall-codex.sh
```

Or:

```bash
curl -fsSL https://raw.githubusercontent.com/kuvarti/claudius-sculptus/master/uninstall-codex.sh | bash
```

The uninstaller restores the original values of owned TOML keys only while their
current values still match this project. A value changed by the user after
installation is preserved. Existing `AGENTS.md` and skill files are restored from
their backups; modified managed files are left in place.

## Safe sandboxes

Test either provider without touching your real home configuration:

```bash
./tests/test-claude-sandbox.sh
./tests/test-codex-sandbox.sh
```

Each interactive sandbox redirects every install target to a unique directory
under `/tmp`. Its menu can run install/uninstall, inspect generated files, and
simulate a user-modified managed file. The directory is deleted on exit.

## Notification sounds

The shared sounds are installed only when notification enhancements are selected:

- Minecraft villager “huh” for input/approval attention.
- Cartoon “eating” for a completed turn.

Claude Code wires these through its `Notification` and `Stop` hooks. Codex routes
its external notification JSON through `codex/notify.sh`.

## Version transition

The `V1.0` tag retains the original Claude-only `install.sh`, `uninstall.sh`, and
`test-sandbox.sh` paths. Releases after that tag use the explicit Claude/Codex
entry-point names documented above.
