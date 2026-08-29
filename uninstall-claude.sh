#!/bin/bash
# Safely removes Claude Code components installed by claudius-sculptus.
#
# Usage:
#   ./uninstall-claude.sh
#   curl -fsSL https://raw.githubusercontent.com/kuvarti/claudius-sculptus/master/uninstall-claude.sh | bash
set -euo pipefail

REPO_URL="https://github.com/kuvarti/claudius-sculptus.git"
CLAUDE_DIR="${CLAUDIUS_SCULPTUS_CLAUDE_TARGET_DIR:-${CLAUDIUS_SCULPTUS_TARGET_DIR:-${HOME}/.claude}}"
SETTINGS="${CLAUDE_DIR}/settings.json"
STATE_DIR="${CLAUDE_DIR}/.claudius-sculptus"
BACKUP_DIR="${STATE_DIR}/backups"
MANIFEST="${STATE_DIR}/manifest.json"

TEMP_REPO=""
WORK_MANIFEST=""
SETTINGS_TMP=""

cleanup() {
  [ -z "$SETTINGS_TMP" ] || [ ! -f "$SETTINGS_TMP" ] || rm -f "$SETTINGS_TMP"
  [ -z "$WORK_MANIFEST" ] || [ ! -f "$WORK_MANIFEST" ] || rm -f "$WORK_MANIFEST"
  [ -z "$TEMP_REPO" ] || [ ! -d "$TEMP_REPO" ] || rm -rf "$TEMP_REPO"
}
trap cleanup EXIT

# The shared safety helpers live in the checkout, so resolve it before asking
# for removal choices. A curl-based uninstall clones only into a temporary dir.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || true)"
if [ -n "${SCRIPT_DIR:-}" ] && [ -f "${SCRIPT_DIR}/claude/settings.snippet.json" ]; then
  REPO_DIR="$SCRIPT_DIR"
  echo "using local checkout -> ${REPO_DIR}"
else
  command -v git >/dev/null || { echo "error: git is required to bootstrap the uninstall" >&2; exit 1; }
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
prompt_open required || exit 1

echo "Choose which Claude Code components to remove:"

REMOVE_STATUS_LINES=false
ask_yes_no "Remove custom status lines?" yes && REMOVE_STATUS_LINES=true

REMOVE_NOTIFICATION_ENHANCEMENTS=false
ask_yes_no "Remove desktop notification and sound enhancements?" yes && \
  REMOVE_NOTIFICATION_ENHANCEMENTS=true

REMOVE_GLOBAL_CLAUDE=false
ask_yes_no "Remove the global CLAUDE.md file?" no && REMOVE_GLOBAL_CLAUDE=true

REMOVE_INIT_COMMAND=false
ask_yes_no "Remove the custom /init command?" yes && REMOVE_INIT_COMMAND=true

if ! $REMOVE_STATUS_LINES &&
   ! $REMOVE_NOTIFICATION_ENHANCEMENTS &&
   ! $REMOVE_GLOBAL_CLAUDE &&
   ! $REMOVE_INIT_COMMAND; then
  echo "nothing selected; uninstall cancelled"
  prompt_close
  exit 0
fi

echo
echo "Selected for removal:"
$REMOVE_STATUS_LINES && echo "  - custom status lines"
$REMOVE_NOTIFICATION_ENHANCEMENTS && echo "  - desktop notification and sound enhancements"
$REMOVE_GLOBAL_CLAUDE && echo "  - global CLAUDE.md"
$REMOVE_INIT_COMMAND && echo "  - custom /init command"
echo

if ! ask_yes_no "Proceed with uninstall?" no; then
  echo "uninstall cancelled"
  prompt_close
  exit 0
fi
prompt_close

HAS_MANIFEST=false
if [ -f "$MANIFEST" ]; then
  manifest_validate_basic "$MANIFEST" claude || {
    echo "error: ${MANIFEST} is invalid; refusing unsafe uninstall" >&2
    exit 1
  }
  HAS_MANIFEST=true
  WORK_MANIFEST="$(mktemp "${STATE_DIR}/uninstall-manifest.XXXXXX")"
  cp "$MANIFEST" "$WORK_MANIFEST"
else
  echo "warning: no install manifest found; only exact source matches will be removed" >&2
fi

if $REMOVE_STATUS_LINES; then
  if $HAS_MANIFEST; then
    managed_component_remove "status_lines"
  else
    managed_file_remove \
      "${CLAUDE_DIR}/statusline-command.sh" \
      "claude/statusline-command.sh" \
      "statusline-command.sh"
    managed_file_remove \
      "${CLAUDE_DIR}/subagent-statusline.sh" \
      "claude/subagent-statusline.sh" \
      "subagent-statusline.sh"
  fi
fi

if $REMOVE_NOTIFICATION_ENHANCEMENTS; then
  if $HAS_MANIFEST; then
    managed_component_remove "notification_enhancements"
  else
    for sound in "${REPO_DIR}/shared/media/"*.mp3; do
      [ -f "$sound" ] || continue
      sound_name="$(basename "$sound")"
      managed_file_remove \
        "${CLAUDE_DIR}/sounds/${sound_name}" \
        "shared/media/${sound_name}" \
        "$sound_name"
    done
  fi
fi

if $REMOVE_GLOBAL_CLAUDE; then
  if $HAS_MANIFEST; then
    managed_component_remove "global_claude"
  else
    managed_file_remove \
      "${CLAUDE_DIR}/CLAUDE.md" \
      "claude/global-CLAUDE.md" \
      "global CLAUDE.md"
  fi
fi

if $REMOVE_INIT_COMMAND; then
  if $HAS_MANIFEST; then
    managed_component_remove "init_command"
  else
    managed_file_remove \
      "${CLAUDE_DIR}/commands/init.md" \
      "claude/commands/init.md" \
      "custom /init command"
  fi
fi

# Remove only settings whose complete values or commands still match this
# project. User-defined status lines and unrelated hooks remain untouched.
if [ -f "$SETTINGS" ] && ($REMOVE_STATUS_LINES || $REMOVE_NOTIFICATION_ENHANCEMENTS); then
  ORIGINAL_STATUS_PRESENT=false
  ORIGINAL_STATUS="null"
  ORIGINAL_SUBAGENT_STATUS_PRESENT=false
  ORIGINAL_SUBAGENT_STATUS="null"
  SETTINGS_FILE_EXISTED=true

  if $HAS_MANIFEST; then
    ORIGINAL_STATUS_PRESENT="$(jq -r '.settings.originalStatusLinePresent // false' "$WORK_MANIFEST")"
    ORIGINAL_STATUS="$(jq -c '.settings.originalStatusLine // null' "$WORK_MANIFEST")"
    ORIGINAL_SUBAGENT_STATUS_PRESENT="$(jq -r '.settings.originalSubagentStatusLinePresent // false' "$WORK_MANIFEST")"
    ORIGINAL_SUBAGENT_STATUS="$(jq -c '.settings.originalSubagentStatusLine // null' "$WORK_MANIFEST")"
    SETTINGS_FILE_EXISTED="$(jq -r '
      if (.settings | has("fileExisted")) then .settings.fileExisted else true end
    ' "$WORK_MANIFEST")"
  fi

  SETTINGS_TMP="$(mktemp)"
  jq \
    --argjson remove_status "$REMOVE_STATUS_LINES" \
    --argjson remove_notifications "$REMOVE_NOTIFICATION_ENHANCEMENTS" \
    --argjson original_status_present "$ORIGINAL_STATUS_PRESENT" \
    --argjson original_status "$ORIGINAL_STATUS" \
    --argjson original_subagent_status_present "$ORIGINAL_SUBAGENT_STATUS_PRESENT" \
    --argjson original_subagent_status "$ORIGINAL_SUBAGENT_STATUS" \
    --slurpfile managed "${REPO_DIR}/claude/settings.snippet.json" '
      def managed_commands($event):
        [$managed[0].hooks[$event][]?.hooks[]?.command];
      def without_managed($commands):
        map(.hooks |= map(.command as $command | select(($commands | index($command)) == null))) |
        map(select((.hooks | length) > 0));

      if $remove_status and .statusLine == $managed[0].statusLine then
        if $original_status_present then .statusLine = $original_status else del(.statusLine) end
      else . end |
      if $remove_status and .subagentStatusLine == $managed[0].subagentStatusLine then
        if $original_subagent_status_present then
          .subagentStatusLine = $original_subagent_status
        else del(.subagentStatusLine) end
      else . end |
      if $remove_notifications and .hooks.Notification? then
        .hooks.Notification |= without_managed(managed_commands("Notification"))
      else . end |
      if $remove_notifications and .hooks.Stop? then
        .hooks.Stop |= without_managed(managed_commands("Stop"))
      else . end |
      if ((.hooks.Notification? // []) | length) == 0 then del(.hooks.Notification) else . end |
      if ((.hooks.Stop? // []) | length) == 0 then del(.hooks.Stop) else . end |
      if ((.hooks? // {}) | length) == 0 then del(.hooks) else . end
    ' "$SETTINGS" > "$SETTINGS_TMP"

  if cmp -s "$SETTINGS" "$SETTINGS_TMP"; then
    rm -f "$SETTINGS_TMP"
  elif $HAS_MANIFEST &&
       [ "$SETTINGS_FILE_EXISTED" = "false" ] &&
       jq -e 'length == 0' "$SETTINGS_TMP" >/dev/null; then
    rm -f "$SETTINGS" "$SETTINGS_TMP"
    echo "removed settings file created by installer -> ${SETTINGS}"
  else
    mv "$SETTINGS_TMP" "$SETTINGS"
    echo "removed matching managed entries from ${SETTINGS}"
  fi
  SETTINGS_TMP=""
fi

rmdir "${CLAUDE_DIR}/sounds" 2>/dev/null || true
rmdir "${CLAUDE_DIR}/commands" 2>/dev/null || true

if $HAS_MANIFEST; then
  manifest_tmp="$(mktemp "${STATE_DIR}/manifest-update.XXXXXX")"
  jq \
    --argjson remove_status "$REMOVE_STATUS_LINES" \
    --argjson remove_notifications "$REMOVE_NOTIFICATION_ENHANCEMENTS" '
      if $remove_status then
        .settings.statusLines = false |
        .settings.originalStatusLinePresent = false |
        .settings.originalStatusLine = null |
        .settings.originalSubagentStatusLinePresent = false |
        .settings.originalSubagentStatusLine = null
      else . end |
      if $remove_notifications then .settings.notificationEnhancements = false else . end
    ' "$WORK_MANIFEST" > "$manifest_tmp"
  mv "$manifest_tmp" "$WORK_MANIFEST"

  remaining="$(jq '
    (.files | length) +
    ([.settings.statusLines, .settings.notificationEnhancements] |
      map(select(. == true)) | length)
  ' "$WORK_MANIFEST")"

  if [ "$remaining" -eq 0 ]; then
    rm -f "$MANIFEST" "$WORK_MANIFEST"
    WORK_MANIFEST=""
    rmdir "$BACKUP_DIR" 2>/dev/null || true
    rmdir "$STATE_DIR" 2>/dev/null || true
    echo "removed uninstall manifest"
  else
    mv "$WORK_MANIFEST" "$MANIFEST"
    WORK_MANIFEST=""
    echo "updated uninstall manifest -> ${MANIFEST}"
  fi
fi

echo "done. Restart Claude Code (or start a new session) to pick up the changes."
