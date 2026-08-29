#!/bin/bash
# Safely removes Codex CLI components installed by claudius-sculptus.
#
# Usage:
#   ./uninstall-codex.sh
#   curl -fsSL https://raw.githubusercontent.com/kuvarti/claudius-sculptus/master/uninstall-codex.sh | bash
set -euo pipefail

REPO_URL="https://github.com/kuvarti/claudius-sculptus.git"
CODEX_DIR="${CLAUDIUS_SCULPTUS_CODEX_TARGET_DIR:-${HOME}/.codex}"
SKILLS_DIR="${CLAUDIUS_SCULPTUS_SKILLS_TARGET_DIR:-${HOME}/.agents/skills}"
CONFIG="${CODEX_DIR}/config.toml"
ASSET_DIR="${CODEX_DIR}/claudius-sculptus"
NOTIFY_SCRIPT="${ASSET_DIR}/notify.sh"
STATE_DIR="${CODEX_DIR}/.claudius-sculptus"
BACKUP_DIR="${STATE_DIR}/backups"
MANIFEST="${STATE_DIR}/manifest.json"

TEMP_REPO=""
WORK_MANIFEST=""
SNAPSHOT_TMP=""

cleanup() {
  [ -z "$SNAPSHOT_TMP" ] || [ ! -f "$SNAPSHOT_TMP" ] || rm -f "$SNAPSHOT_TMP"
  [ -z "$WORK_MANIFEST" ] || [ ! -f "$WORK_MANIFEST" ] || rm -f "$WORK_MANIFEST"
  [ -z "$TEMP_REPO" ] || [ ! -d "$TEMP_REPO" ] || rm -rf "$TEMP_REPO"
}
trap cleanup EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || true)"
if [ -n "${SCRIPT_DIR:-}" ] && [ -f "${SCRIPT_DIR}/codex/config.snippet.toml" ]; then
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
require_command python3
python3 -c 'import tomllib' >/dev/null 2>&1 || {
  echo "error: Codex configuration requires Python 3.11 or newer (tomllib)" >&2
  exit 1
}
prompt_open required || exit 1

echo "Choose which Codex components to remove:"

REMOVE_STATUS_LINE=false
ask_yes_no "Remove the native Codex status-line configuration?" yes && REMOVE_STATUS_LINE=true

REMOVE_NOTIFICATION_ENHANCEMENTS=false
ask_yes_no "Remove desktop notification and sound enhancements?" yes && \
  REMOVE_NOTIFICATION_ENHANCEMENTS=true

REMOVE_GLOBAL_AGENTS=false
ask_yes_no "Remove the global AGENTS.md file?" no && REMOVE_GLOBAL_AGENTS=true

REMOVE_PROJECT_INIT_SKILL=false
ask_yes_no 'Remove the $project-init skill?' yes && REMOVE_PROJECT_INIT_SKILL=true

if ! $REMOVE_STATUS_LINE &&
   ! $REMOVE_NOTIFICATION_ENHANCEMENTS &&
   ! $REMOVE_GLOBAL_AGENTS &&
   ! $REMOVE_PROJECT_INIT_SKILL; then
  echo "nothing selected; uninstall cancelled"
  prompt_close
  exit 0
fi

echo
echo "Selected for removal:"
$REMOVE_STATUS_LINE && echo "  - native Codex status-line configuration"
$REMOVE_NOTIFICATION_ENHANCEMENTS && echo "  - desktop notification and sound enhancements"
$REMOVE_GLOBAL_AGENTS && echo "  - global AGENTS.md"
$REMOVE_PROJECT_INIT_SKILL && echo '  - $project-init skill'
echo

if ! ask_yes_no "Proceed with uninstall?" no; then
  echo "uninstall cancelled"
  prompt_close
  exit 0
fi
prompt_close

HAS_MANIFEST=false
if [ -f "$MANIFEST" ]; then
  manifest_validate_basic "$MANIFEST" codex || {
    echo "error: ${MANIFEST} is invalid; refusing unsafe uninstall" >&2
    exit 1
  }
  HAS_MANIFEST=true
  WORK_MANIFEST="$(mktemp "${STATE_DIR}/uninstall-manifest.XXXXXX")"
  cp "$MANIFEST" "$WORK_MANIFEST"
else
  echo "warning: no install manifest found; only exact managed values will be removed" >&2
fi

CONFIG_COMPONENTS=()
if $REMOVE_STATUS_LINE; then CONFIG_COMPONENTS+=(status-line); fi
if $REMOVE_NOTIFICATION_ENHANCEMENTS; then CONFIG_COMPONENTS+=(notifications); fi

if [ -f "$CONFIG" ] && [ "${#CONFIG_COMPONENTS[@]}" -gt 0 ]; then
  if $HAS_MANIFEST; then
    if $REMOVE_STATUS_LINE; then
      SNAPSHOT_TMP="$(mktemp)"
      jq '.settings.statusLineOriginal // {fileExisted: true, values: {}}' \
        "$WORK_MANIFEST" > "$SNAPSHOT_TMP"
      python3 "${REPO_DIR}/codex/config_editor.py" restore \
        "$CONFIG" \
        "${REPO_DIR}/codex/config.snippet.toml" \
        "$NOTIFY_SCRIPT" \
        "$SNAPSHOT_TMP" \
        status-line
      rm -f "$SNAPSHOT_TMP"
      SNAPSHOT_TMP=""
    fi
    if $REMOVE_NOTIFICATION_ENHANCEMENTS; then
      SNAPSHOT_TMP="$(mktemp)"
      jq '.settings.notificationsOriginal // {fileExisted: true, values: {}}' \
        "$WORK_MANIFEST" > "$SNAPSHOT_TMP"
      python3 "${REPO_DIR}/codex/config_editor.py" restore \
        "$CONFIG" \
        "${REPO_DIR}/codex/config.snippet.toml" \
        "$NOTIFY_SCRIPT" \
        "$SNAPSHOT_TMP" \
        notifications
      rm -f "$SNAPSHOT_TMP"
      SNAPSHOT_TMP=""
    fi
  else
    python3 "${REPO_DIR}/codex/config_editor.py" remove-managed \
      "$CONFIG" \
      "${REPO_DIR}/codex/config.snippet.toml" \
      "$NOTIFY_SCRIPT" \
      "${CONFIG_COMPONENTS[@]}"
  fi
  echo "removed matching managed settings from ${CONFIG}"
fi

if $REMOVE_NOTIFICATION_ENHANCEMENTS; then
  if $HAS_MANIFEST; then
    managed_component_remove "notification_enhancements"
  else
    managed_file_remove "$NOTIFY_SCRIPT" "codex/notify.sh" "Codex notifier"
    for sound in "${REPO_DIR}/shared/media/"*.mp3; do
      [ -f "$sound" ] || continue
      sound_name="$(basename "$sound")"
      managed_file_remove \
        "${ASSET_DIR}/sounds/${sound_name}" \
        "shared/media/${sound_name}" \
        "$sound_name"
    done
  fi
fi

if $REMOVE_GLOBAL_AGENTS; then
  if $HAS_MANIFEST; then
    managed_component_remove "global_agents"
  else
    managed_file_remove \
      "${CODEX_DIR}/AGENTS.md" \
      "codex/global-AGENTS.md" \
      "global AGENTS.md"
  fi
fi

if $REMOVE_PROJECT_INIT_SKILL; then
  if $HAS_MANIFEST; then
    managed_component_remove "project_init_skill"
  else
    managed_file_remove \
      "${SKILLS_DIR}/project-init/SKILL.md" \
      "codex/skills/project-init/SKILL.md" \
      'project-init SKILL.md'
  fi
fi

rmdir "${ASSET_DIR}/sounds" 2>/dev/null || true
rmdir "$ASSET_DIR" 2>/dev/null || true
rmdir "${SKILLS_DIR}/project-init" 2>/dev/null || true

if $HAS_MANIFEST; then
  manifest_tmp="$(mktemp "${STATE_DIR}/manifest-update.XXXXXX")"
  jq \
    --argjson remove_status "$REMOVE_STATUS_LINE" \
    --argjson remove_notifications "$REMOVE_NOTIFICATION_ENHANCEMENTS" '
      if $remove_status then
        .settings.statusLine = false |
        .settings.statusLineOriginal = null
      else . end |
      if $remove_notifications then
        .settings.notificationEnhancements = false |
        .settings.notificationsOriginal = null
      else . end
    ' "$WORK_MANIFEST" > "$manifest_tmp"
  mv "$manifest_tmp" "$WORK_MANIFEST"

  config_components_remaining="$(jq -r '
    (.settings.statusLine // false) or (.settings.notificationEnhancements // false)
  ' "$WORK_MANIFEST")"
  config_file_existed="$(jq -r '
    if (.settings | has("configFileExisted")) then
      .settings.configFileExisted
    else true end
  ' "$WORK_MANIFEST")"
  if [ "$config_components_remaining" != "true" ] &&
     [ "$config_file_existed" = "false" ] &&
     [ -f "$CONFIG" ] &&
     python3 "${REPO_DIR}/codex/config_editor.py" is-empty "$CONFIG"; then
    rm -f "$CONFIG"
    echo "removed config file created by installer -> ${CONFIG}"
  fi

  remaining="$(jq '
    (.files | length) +
    ([.settings.statusLine, .settings.notificationEnhancements] |
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

echo "done. Restart Codex (or start a new session) to pick up the changes."
