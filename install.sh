#!/bin/bash
# Installs the Claude Code status line scripts, notification sounds, and the
# system-wide CLAUDE.md into ~/.claude and merges the statusLine /
# subagentStatusLine / hooks settings into ~/.claude/settings.json.
#
# Notification sounds require ffplay (from ffmpeg).
#
# Usage: ./install.sh
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${HOME}/.claude"
SETTINGS="${CLAUDE_DIR}/settings.json"

command -v jq >/dev/null || { echo "error: jq is required" >&2; exit 1; }
mkdir -p "$CLAUDE_DIR"

# 1. Copy the scripts (preserves the raw ANSI escape bytes).
cp "${REPO_DIR}/statusline-command.sh"  "${CLAUDE_DIR}/statusline-command.sh"
cp "${REPO_DIR}/subagent-statusline.sh" "${CLAUDE_DIR}/subagent-statusline.sh"
chmod +x "${CLAUDE_DIR}/statusline-command.sh" "${CLAUDE_DIR}/subagent-statusline.sh"
echo "installed scripts -> ${CLAUDE_DIR}/"

# 1b. Copy notification sounds (referenced by the Notification/Stop hooks).
mkdir -p "${CLAUDE_DIR}/sounds"
cp "${REPO_DIR}/media/"*.mp3 "${CLAUDE_DIR}/sounds/"
echo "installed sounds -> ${CLAUDE_DIR}/sounds/"
command -v ffplay >/dev/null || \
  echo "warning: ffplay not found; notification sounds won't play (install ffmpeg)" >&2

# 1c. Install the system-wide CLAUDE.md (applies to every session on this machine).
cp "${REPO_DIR}/global-CLAUDE.md" "${CLAUDE_DIR}/CLAUDE.md"
echo "installed system-wide CLAUDE.md -> ${CLAUDE_DIR}/CLAUDE.md"

# 2. Merge the keys into settings.json (creating it if absent).
if [ -f "$SETTINGS" ]; then
  tmp="$(mktemp)"
  jq -s '.[0] * .[1]' "$SETTINGS" "${REPO_DIR}/settings.snippet.json" > "$tmp"
  mv "$tmp" "$SETTINGS"
  echo "merged statusLine/subagentStatusLine into existing ${SETTINGS}"
else
  cp "${REPO_DIR}/settings.snippet.json" "$SETTINGS"
  echo "created ${SETTINGS} from snippet"
fi

echo "done. Restart Claude Code (or start a new session) to pick up the changes."
