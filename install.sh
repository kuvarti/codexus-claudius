#!/bin/bash
# Installs the Claude Code status line scripts into ~/.claude and merges the
# statusLine / subagentStatusLine settings into ~/.claude/settings.json.
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

# 2. Merge the two keys into settings.json (creating it if absent).
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
