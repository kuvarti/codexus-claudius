#!/bin/bash
# Installs the Claude Code status lines and optional enhancements into ~/.claude.
# A manifest records installed files, checksums, and backups for safe uninstall.
#
# Usage:
#   ./install-claude.sh
#   curl -fsSL https://raw.githubusercontent.com/kuvarti/claudius-sculptus/master/install-claude.sh | bash
set -euo pipefail

REPO_URL="https://github.com/kuvarti/claudius-sculptus.git"
CLAUDE_DIR="${CLAUDIUS_SCULPTUS_CLAUDE_TARGET_DIR:-${CLAUDIUS_SCULPTUS_TARGET_DIR:-${HOME}/.claude}}"
SETTINGS="${CLAUDE_DIR}/settings.json"
STATE_DIR="${CLAUDE_DIR}/.claudius-sculptus"
BACKUP_DIR="${STATE_DIR}/backups"
MANIFEST="${STATE_DIR}/manifest.json"

TEMP_REPO=""
WORK_MANIFEST=""
SELECTED_SETTINGS=""
BASE_SETTINGS=""
SETTINGS_TMP=""

cleanup() {
  [ -z "$SETTINGS_TMP" ] || [ ! -f "$SETTINGS_TMP" ] || rm -f "$SETTINGS_TMP"
  [ -z "$SELECTED_SETTINGS" ] || [ ! -f "$SELECTED_SETTINGS" ] || rm -f "$SELECTED_SETTINGS"
  if [ -n "$BASE_SETTINGS" ] && [ "$BASE_SETTINGS" != "$SETTINGS" ] && [ -f "$BASE_SETTINGS" ]; then
    rm -f "$BASE_SETTINGS"
  fi
  [ -z "$WORK_MANIFEST" ] || [ ! -f "$WORK_MANIFEST" ] || rm -f "$WORK_MANIFEST"
  [ -z "$TEMP_REPO" ] || [ ! -d "$TEMP_REPO" ] || rm -rf "$TEMP_REPO"
}
trap cleanup EXIT

# Use the checkout containing this script, or clone the repository when the
# entry point is piped to bash.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || true)"
if [ -n "${SCRIPT_DIR:-}" ] && [ -f "${SCRIPT_DIR}/claude/global-CLAUDE.md" ]; then
  REPO_DIR="$SCRIPT_DIR"
  echo "using local checkout -> ${REPO_DIR}"
else
  command -v git >/dev/null || { echo "error: git is required to bootstrap the install" >&2; exit 1; }
  TEMP_REPO="$(mktemp -d)"
  REPO_DIR="$TEMP_REPO"
  echo "cloning ${REPO_URL} ..."
  git clone --depth 1 "$REPO_URL" "$REPO_DIR" >/dev/null 2>&1 \
    || { echo "error: git clone failed (is the repo public and pushed?)" >&2; exit 1; }
fi

# shellcheck source=shared/lib/platform.sh
source "${REPO_DIR}/shared/lib/platform.sh"
# shellcheck source=shared/lib/prompts.sh
source "${REPO_DIR}/shared/lib/prompts.sh"
# shellcheck source=shared/lib/manifest.sh
source "${REPO_DIR}/shared/lib/manifest.sh"
# shellcheck source=shared/lib/files.sh
source "${REPO_DIR}/shared/lib/files.sh"

require_command jq
require_command sha256sum

prompt_open optional
echo "Choose which optional Claude Code components to install (the default is yes):"

INSTALL_GLOBAL_CLAUDE=false
ask_yes_no "Install the global CLAUDE.md file?" yes && INSTALL_GLOBAL_CLAUDE=true

INSTALL_NOTIFICATION_ENHANCEMENTS=false
ask_yes_no "Enhance notifications with desktop alerts and sound effects?" yes && \
  INSTALL_NOTIFICATION_ENHANCEMENTS=true

INSTALL_INIT_COMMAND=false
ask_yes_no "Install the custom /init command?" yes && INSTALL_INIT_COMMAND=true

if [ -z "$PROMPT_FD" ]; then
  echo "no interactive terminal detected; using the default choices"
fi
prompt_close

mkdir -p "$CLAUDE_DIR" "$BACKUP_DIR"

if [ -f "$MANIFEST" ]; then
  manifest_validate_basic "$MANIFEST" claude || {
    echo "error: ${MANIFEST} is invalid; refusing to overwrite uninstall state" >&2
    exit 1
  }
fi

WORK_MANIFEST="$(mktemp "${STATE_DIR}/manifest.XXXXXX")"
if [ -f "$MANIFEST" ]; then
  cp "$MANIFEST" "$WORK_MANIFEST"
else
  jq -n '{
    schemaVersion: 1,
    provider: "claude",
    installedAt: null,
    files: {},
    settings: {
      statusLines: false,
      notificationEnhancements: false,
      fileExisted: false,
      originalStatusLinePresent: false,
      originalStatusLine: null,
      originalSubagentStatusLinePresent: false,
      originalSubagentStatusLine: null
    }
  }' > "$WORK_MANIFEST"
fi

# Status lines are the core Claude Code component and are always installed.
managed_file_install \
  "claude/statusline-command.sh" \
  "${CLAUDE_DIR}/statusline-command.sh" \
  "status_lines" \
  "statusline-command.sh.original"
managed_file_install \
  "claude/subagent-statusline.sh" \
  "${CLAUDE_DIR}/subagent-statusline.sh" \
  "status_lines" \
  "subagent-statusline.sh.original"
chmod +x "${CLAUDE_DIR}/statusline-command.sh" "${CLAUDE_DIR}/subagent-statusline.sh"
echo "installed status line scripts -> ${CLAUDE_DIR}/"

if $INSTALL_NOTIFICATION_ENHANCEMENTS; then
  for sound in "${REPO_DIR}/shared/media/"*.mp3; do
    sound_name="$(basename "$sound")"
    managed_file_install \
      "shared/media/${sound_name}" \
      "${CLAUDE_DIR}/sounds/${sound_name}" \
      "notification_enhancements" \
      "sound-${sound_name}.original"
  done
  echo "installed notification sounds -> ${CLAUDE_DIR}/sounds/"
  warn_notification_dependencies
else
  echo "skipped desktop notifications and sound effects"
fi

if $INSTALL_GLOBAL_CLAUDE; then
  managed_file_install \
    "claude/global-CLAUDE.md" \
    "${CLAUDE_DIR}/CLAUDE.md" \
    "global_claude" \
    "global-CLAUDE.md.original"
  echo "installed system-wide CLAUDE.md -> ${CLAUDE_DIR}/CLAUDE.md"
else
  echo "skipped global CLAUDE.md"
fi

if $INSTALL_INIT_COMMAND; then
  managed_file_install \
    "claude/commands/init.md" \
    "${CLAUDE_DIR}/commands/init.md" \
    "init_command" \
    "command-init.md.original"
  echo "installed custom /init command -> ${CLAUDE_DIR}/commands/init.md"
else
  echo "skipped custom /init command"
fi

# Save the pre-install status-line settings only the first time they are managed.
if ! jq -e '.settings.statusLines == true' "$WORK_MANIFEST" >/dev/null; then
  manifest_tmp="$(mktemp "${STATE_DIR}/manifest-update.XXXXXX")"
  if [ -f "$SETTINGS" ]; then
    jq --slurpfile current "$SETTINGS" '
      .settings.fileExisted = true |
      .settings.originalStatusLinePresent = ($current[0] | has("statusLine")) |
      .settings.originalStatusLine = ($current[0].statusLine // null) |
      .settings.originalSubagentStatusLinePresent = ($current[0] | has("subagentStatusLine")) |
      .settings.originalSubagentStatusLine = ($current[0].subagentStatusLine // null)
    ' "$WORK_MANIFEST" > "$manifest_tmp"
  else
    jq '
      .settings.fileExisted = false |
      .settings.originalStatusLinePresent = false |
      .settings.originalStatusLine = null |
      .settings.originalSubagentStatusLinePresent = false |
      .settings.originalSubagentStatusLine = null
    ' "$WORK_MANIFEST" > "$manifest_tmp"
  fi
  mv "$manifest_tmp" "$WORK_MANIFEST"
fi

# Build the selected settings and merge them without duplicating managed hooks.
SELECTED_SETTINGS="$(mktemp)"
if $INSTALL_NOTIFICATION_ENHANCEMENTS; then
  cp "${REPO_DIR}/claude/settings.snippet.json" "$SELECTED_SETTINGS"
else
  jq 'del(.hooks)' "${REPO_DIR}/claude/settings.snippet.json" > "$SELECTED_SETTINGS"
fi

if [ -f "$SETTINGS" ]; then
  BASE_SETTINGS="$(mktemp)"
  jq --slurpfile managed "${REPO_DIR}/claude/settings.snippet.json" '
    def managed_commands($event):
      [$managed[0].hooks[$event][]?.hooks[]?.command];
    def without_managed($commands):
      map(.hooks |= map(.command as $command | select(($commands | index($command)) == null))) |
      map(select((.hooks | length) > 0));

    if .hooks.Notification? then
      .hooks.Notification |= without_managed(managed_commands("Notification"))
    else . end |
    if .hooks.Stop? then
      .hooks.Stop |= without_managed(managed_commands("Stop"))
    else . end |
    if ((.hooks.Notification? // []) | length) == 0 then del(.hooks.Notification) else . end |
    if ((.hooks.Stop? // []) | length) == 0 then del(.hooks.Stop) else . end |
    if ((.hooks? // {}) | length) == 0 then del(.hooks) else . end
  ' "$SETTINGS" > "$BASE_SETTINGS"

  SETTINGS_TMP="$(mktemp)"
  jq -s '
    .[0] as $current |
    .[1] as $selected |
    ($current * ($selected | del(.hooks))) |
    if $selected.hooks? then
      .hooks.Notification = (($current.hooks.Notification // []) + ($selected.hooks.Notification // [])) |
      .hooks.Stop = (($current.hooks.Stop // []) + ($selected.hooks.Stop // []))
    else . end
  ' "$BASE_SETTINGS" "$SELECTED_SETTINGS" > "$SETTINGS_TMP"
  mv "$SETTINGS_TMP" "$SETTINGS"
  SETTINGS_TMP=""
  rm -f "$BASE_SETTINGS"
  BASE_SETTINGS=""
  echo "merged managed settings into existing ${SETTINGS}"
else
  cp "$SELECTED_SETTINGS" "$SETTINGS"
  echo "created ${SETTINGS} from selected settings"
fi
rm -f "$SELECTED_SETTINGS"
SELECTED_SETTINGS=""

manifest_tmp="$(mktemp "${STATE_DIR}/manifest-update.XXXXXX")"
jq \
  --arg installed_at "$(utc_timestamp)" \
  --argjson notifications "$INSTALL_NOTIFICATION_ENHANCEMENTS" '
    .provider = "claude" |
    .installedAt = $installed_at |
    .settings.statusLines = true |
    .settings.notificationEnhancements = $notifications
  ' "$WORK_MANIFEST" > "$manifest_tmp"
mv "$manifest_tmp" "$WORK_MANIFEST"
mv "$WORK_MANIFEST" "$MANIFEST"
WORK_MANIFEST=""
echo "saved uninstall manifest -> ${MANIFEST}"

echo "done. Restart Claude Code (or start a new session) to pick up the changes."
