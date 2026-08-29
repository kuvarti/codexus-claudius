#!/bin/bash
# Installs optional Codex CLI enhancements into ~/.codex and ~/.agents/skills.
# A manifest records installed files, checksums, original config values, and backups.
#
# Usage:
#   ./install-codex.sh
#   curl -fsSL https://raw.githubusercontent.com/kuvarti/claudius-sculptus/master/install-codex.sh | bash
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
require_command python3
python3 -c 'import tomllib' >/dev/null 2>&1 || {
  echo "error: Codex configuration requires Python 3.11 or newer (tomllib)" >&2
  exit 1
}

prompt_open optional
echo "Choose which optional Codex components to install (the default is yes):"

INSTALL_STATUS_LINE=false
ask_yes_no "Configure the native Codex status line?" yes && INSTALL_STATUS_LINE=true

INSTALL_NOTIFICATION_ENHANCEMENTS=false
ask_yes_no "Enhance notifications with desktop alerts and sound effects?" yes && \
  INSTALL_NOTIFICATION_ENHANCEMENTS=true

INSTALL_GLOBAL_AGENTS=false
ask_yes_no "Install the global AGENTS.md file?" yes && INSTALL_GLOBAL_AGENTS=true

INSTALL_PROJECT_INIT_SKILL=false
ask_yes_no 'Install the $project-init skill?' yes && INSTALL_PROJECT_INIT_SKILL=true

if [ -z "$PROMPT_FD" ]; then
  echo "no interactive terminal detected; using the default choices"
fi
prompt_close

mkdir -p "$CODEX_DIR" "$SKILLS_DIR" "$BACKUP_DIR"

if [ -f "$MANIFEST" ]; then
  manifest_validate_basic "$MANIFEST" codex || {
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
    provider: "codex",
    installedAt: null,
    files: {},
    settings: {
      statusLine: false,
      notificationEnhancements: false,
      configFileExisted: false,
      statusLineOriginal: null,
      notificationsOriginal: null
    }
  }' > "$WORK_MANIFEST"
fi

CONFIG_WAS_MANAGED="$(jq -r '
  (.settings.statusLine // false) or (.settings.notificationEnhancements // false)
' "$WORK_MANIFEST")"
if ($INSTALL_STATUS_LINE || $INSTALL_NOTIFICATION_ENHANCEMENTS) && \
   [ "$CONFIG_WAS_MANAGED" != "true" ]; then
  manifest_tmp="$(mktemp "${STATE_DIR}/manifest-update.XXXXXX")"
  if [ -f "$CONFIG" ]; then config_existed=true; else config_existed=false; fi
  jq --argjson existed "$config_existed" \
    '.settings.configFileExisted = $existed' \
    "$WORK_MANIFEST" > "$manifest_tmp"
  mv "$manifest_tmp" "$WORK_MANIFEST"
fi

CONFIG_COMPONENTS=()
if $INSTALL_STATUS_LINE; then
  if ! jq -e '.settings.statusLine == true' "$WORK_MANIFEST" >/dev/null; then
    SNAPSHOT_TMP="$(mktemp)"
    python3 "${REPO_DIR}/codex/config_editor.py" snapshot \
      "$CONFIG" status-line > "$SNAPSHOT_TMP"
    manifest_tmp="$(mktemp "${STATE_DIR}/manifest-update.XXXXXX")"
    jq --slurpfile snapshot "$SNAPSHOT_TMP" \
      '.settings.statusLineOriginal = $snapshot[0]' \
      "$WORK_MANIFEST" > "$manifest_tmp"
    mv "$manifest_tmp" "$WORK_MANIFEST"
    rm -f "$SNAPSHOT_TMP"
    SNAPSHOT_TMP=""
  fi
  CONFIG_COMPONENTS+=(status-line)
fi

if $INSTALL_NOTIFICATION_ENHANCEMENTS; then
  if ! jq -e '.settings.notificationEnhancements == true' "$WORK_MANIFEST" >/dev/null; then
    SNAPSHOT_TMP="$(mktemp)"
    python3 "${REPO_DIR}/codex/config_editor.py" snapshot \
      "$CONFIG" notifications > "$SNAPSHOT_TMP"
    manifest_tmp="$(mktemp "${STATE_DIR}/manifest-update.XXXXXX")"
    jq --slurpfile snapshot "$SNAPSHOT_TMP" \
      '.settings.notificationsOriginal = $snapshot[0]' \
      "$WORK_MANIFEST" > "$manifest_tmp"
    mv "$manifest_tmp" "$WORK_MANIFEST"
    rm -f "$SNAPSHOT_TMP"
    SNAPSHOT_TMP=""
  fi
  CONFIG_COMPONENTS+=(notifications)

  managed_file_install \
    "codex/notify.sh" \
    "$NOTIFY_SCRIPT" \
    "notification_enhancements" \
    "codex-notify.sh.original"
  chmod +x "$NOTIFY_SCRIPT"

  for sound in "${REPO_DIR}/shared/media/"*.mp3; do
    sound_name="$(basename "$sound")"
    managed_file_install \
      "shared/media/${sound_name}" \
      "${ASSET_DIR}/sounds/${sound_name}" \
      "notification_enhancements" \
      "codex-sound-${sound_name}.original"
  done
  echo "installed Codex notification enhancements -> ${ASSET_DIR}/"
  warn_notification_dependencies
else
  echo "skipped desktop notifications and sound effects"
fi

if [ "${#CONFIG_COMPONENTS[@]}" -gt 0 ]; then
  python3 "${REPO_DIR}/codex/config_editor.py" apply \
    "$CONFIG" \
    "${REPO_DIR}/codex/config.snippet.toml" \
    "$NOTIFY_SCRIPT" \
    "${CONFIG_COMPONENTS[@]}"
  echo "merged managed settings into ${CONFIG}"
fi

if $INSTALL_GLOBAL_AGENTS; then
  managed_file_install \
    "codex/global-AGENTS.md" \
    "${CODEX_DIR}/AGENTS.md" \
    "global_agents" \
    "global-AGENTS.md.original"
  echo "installed global AGENTS.md -> ${CODEX_DIR}/AGENTS.md"
else
  echo "skipped global AGENTS.md"
fi

if $INSTALL_PROJECT_INIT_SKILL; then
  managed_file_install \
    "codex/skills/project-init/SKILL.md" \
    "${SKILLS_DIR}/project-init/SKILL.md" \
    "project_init_skill" \
    "project-init-SKILL.md.original"
  echo 'installed $project-init skill ->' "${SKILLS_DIR}/project-init/SKILL.md"
else
  echo 'skipped $project-init skill'
fi

manifest_tmp="$(mktemp "${STATE_DIR}/manifest-update.XXXXXX")"
jq \
  --arg installed_at "$(utc_timestamp)" \
  --argjson status "$INSTALL_STATUS_LINE" \
  --argjson notifications "$INSTALL_NOTIFICATION_ENHANCEMENTS" '
    .provider = "codex" |
    .installedAt = $installed_at |
    if $status then .settings.statusLine = true else . end |
    if $notifications then .settings.notificationEnhancements = true else . end
  ' "$WORK_MANIFEST" > "$manifest_tmp"
mv "$manifest_tmp" "$WORK_MANIFEST"
mv "$WORK_MANIFEST" "$MANIFEST"
WORK_MANIFEST=""
echo "saved uninstall manifest -> ${MANIFEST}"

echo "done. Restart Codex (or start a new session) to pick up the changes."
