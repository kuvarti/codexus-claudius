#!/bin/bash
# Installs the Claude Code status lines and optional enhancements into ~/.claude.
# A manifest records installed files, checksums, and backups for safe uninstall.
#
# Notification sounds require ffplay (from ffmpeg).
#
# Usage:
#   ./install.sh   (from a local checkout)
#   curl -fsSL https://raw.githubusercontent.com/kuvarti/claudius-sculptus/master/install.sh | bash
set -euo pipefail

REPO_URL="https://github.com/kuvarti/claudius-sculptus.git"
CLAUDE_DIR="${CLAUDIUS_SCULPTUS_TARGET_DIR:-${HOME}/.claude}"
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

command -v jq >/dev/null || { echo "error: jq is required" >&2; exit 1; }
command -v sha256sum >/dev/null || { echo "error: sha256sum is required" >&2; exit 1; }

# Read answers from the controlling terminal so prompts still work when the
# installer itself is piped to bash. Fall back to the default choices when no
# interactive terminal is available (for example, in CI).
PROMPT_FD=""
if { exec 3<>/dev/tty; } 2>/dev/null; then
  PROMPT_FD=3
fi

ask_yes_no() {
  local question="$1"
  local answer

  if [ -z "$PROMPT_FD" ]; then
    return 0
  fi

  while true; do
    printf '%s [Y/n] ' "$question" >&"$PROMPT_FD"
    if ! IFS= read -r answer <&"$PROMPT_FD"; then
      printf '\n' >&"$PROMPT_FD"
      return 0
    fi

    case "$answer" in
      ""|[Yy]|[Yy][Ee][Ss]) return 0 ;;
      [Nn]|[Nn][Oo]) return 1 ;;
      *) printf 'Please answer yes or no.\n' >&"$PROMPT_FD" ;;
    esac
  done
}

echo "Choose which optional components to install (the default is yes):"

INSTALL_GLOBAL_CLAUDE=false
if ask_yes_no "Install the global CLAUDE.md file?"; then
  INSTALL_GLOBAL_CLAUDE=true
fi

INSTALL_NOTIFICATION_ENHANCEMENTS=false
if ask_yes_no "Enhance notifications with desktop alerts and sound effects?"; then
  INSTALL_NOTIFICATION_ENHANCEMENTS=true
fi

INSTALL_INIT_COMMAND=false
if ask_yes_no "Install the custom /init command?"; then
  INSTALL_INIT_COMMAND=true
fi

if [ -z "$PROMPT_FD" ]; then
  echo "no interactive terminal detected; using the default choices"
else
  exec 3>&-
fi

# Source files: use the local checkout when this script sits next to them,
# otherwise clone from GitHub so it also works via `curl ... | bash`.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || true)"
if [ -n "${SCRIPT_DIR:-}" ] && [ -f "${SCRIPT_DIR}/global-CLAUDE.md" ]; then
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

mkdir -p "$CLAUDE_DIR" "$BACKUP_DIR"

if [ -f "$MANIFEST" ]; then
  jq -e '
    .schemaVersion == 1 and
    (.files | type == "object") and
    (.settings | type == "object")
  ' "$MANIFEST" >/dev/null || {
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

install_managed_file() {
  local source_rel="$1"
  local target="$2"
  local component="$3"
  local backup_name="$4"
  local source="${REPO_DIR}/${source_rel}"
  local backup_rel=""
  local checksum
  local manifest_tmp

  [ -f "$source" ] || { echo "error: source file not found: ${source}" >&2; return 1; }
  mkdir -p "$(dirname "$target")"

  if jq -e --arg path "$target" '.files[$path] != null' "$WORK_MANIFEST" >/dev/null; then
    backup_rel="$(jq -r --arg path "$target" '.files[$path].backup // ""' "$WORK_MANIFEST")"
  elif [ -e "$target" ] || [ -L "$target" ]; then
    backup_rel="backups/${backup_name}"
    cp -p "$target" "${STATE_DIR}/${backup_rel}"
    echo "backed up existing file -> ${STATE_DIR}/${backup_rel}"
  fi

  cp "$source" "$target"
  checksum="$(sha256sum "$target" | awk '{print $1}')"
  manifest_tmp="$(mktemp "${STATE_DIR}/manifest-update.XXXXXX")"
  jq \
    --arg path "$target" \
    --arg component "$component" \
    --arg source "$source_rel" \
    --arg checksum "$checksum" \
    --arg backup "$backup_rel" '
      .files[$path] = {
        component: $component,
        source: $source,
        sha256: $checksum,
        backup: (if $backup == "" then null else $backup end)
      }
    ' "$WORK_MANIFEST" > "$manifest_tmp"
  mv "$manifest_tmp" "$WORK_MANIFEST"
}

# 1. Status lines are the core component and are always installed.
install_managed_file \
  "statusline-command.sh" \
  "${CLAUDE_DIR}/statusline-command.sh" \
  "status_lines" \
  "statusline-command.sh.original"
install_managed_file \
  "subagent-statusline.sh" \
  "${CLAUDE_DIR}/subagent-statusline.sh" \
  "status_lines" \
  "subagent-statusline.sh.original"
chmod +x "${CLAUDE_DIR}/statusline-command.sh" "${CLAUDE_DIR}/subagent-statusline.sh"
echo "installed status line scripts -> ${CLAUDE_DIR}/"

# 2. Optional notification sounds. Desktop notification hooks are applied with
# the settings below as part of the same enhancement choice.
if $INSTALL_NOTIFICATION_ENHANCEMENTS; then
  for sound in "${REPO_DIR}/media/"*.mp3; do
    sound_name="$(basename "$sound")"
    install_managed_file \
      "media/${sound_name}" \
      "${CLAUDE_DIR}/sounds/${sound_name}" \
      "notification_enhancements" \
      "sound-${sound_name}.original"
  done
  echo "installed notification sounds -> ${CLAUDE_DIR}/sounds/"
  command -v notify-send >/dev/null || \
    echo "warning: notify-send not found; desktop notifications won't appear" >&2
  command -v ffplay >/dev/null || \
    echo "warning: ffplay not found; notification sounds won't play (install ffmpeg)" >&2
else
  echo "skipped desktop notifications and sound effects"
fi

# 3. Optional system-wide CLAUDE.md.
if $INSTALL_GLOBAL_CLAUDE; then
  install_managed_file \
    "global-CLAUDE.md" \
    "${CLAUDE_DIR}/CLAUDE.md" \
    "global_claude" \
    "global-CLAUDE.md.original"
  echo "installed system-wide CLAUDE.md -> ${CLAUDE_DIR}/CLAUDE.md"
else
  echo "skipped global CLAUDE.md"
fi

# 4. Optional custom /init command.
if $INSTALL_INIT_COMMAND; then
  install_managed_file \
    "commands/init.md" \
    "${CLAUDE_DIR}/commands/init.md" \
    "init_command" \
    "command-init.md.original"
  echo "installed custom /init command -> ${CLAUDE_DIR}/commands/init.md"
else
  echo "skipped custom /init command"
fi

# 5. Remember pre-install status-line settings the first time they are managed,
# so uninstall can restore them instead of simply deleting them.
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

# 6. Build the selected settings and merge them into settings.json.
SELECTED_SETTINGS="$(mktemp)"
if $INSTALL_NOTIFICATION_ENHANCEMENTS; then
  cp "${REPO_DIR}/settings.snippet.json" "$SELECTED_SETTINGS"
else
  jq 'del(.hooks)' "${REPO_DIR}/settings.snippet.json" > "$SELECTED_SETTINGS"
fi

if [ -f "$SETTINGS" ]; then
  # Remove old copies of our commands before adding the selected hooks. This
  # prevents duplicates while preserving unrelated hooks on the same events.
  BASE_SETTINGS="$(mktemp)"
  jq --slurpfile managed "${REPO_DIR}/settings.snippet.json" '
    def managed_commands($event):
      [$managed[0].hooks[$event][]?.hooks[]?.command];
    def without_managed($commands):
      map(
        .hooks |= map(
          .command as $command |
          select(($commands | index($command)) == null)
        )
      ) |
      map(select((.hooks | length) > 0));

    if .hooks.Notification? then
      .hooks.Notification |= without_managed(managed_commands("Notification"))
    else . end |
    if .hooks.Stop? then
      .hooks.Stop |= without_managed(managed_commands("Stop"))
    else . end |
    if ((.hooks.Notification? // []) | length) == 0 then
      del(.hooks.Notification)
    else . end |
    if ((.hooks.Stop? // []) | length) == 0 then
      del(.hooks.Stop)
    else . end |
    if ((.hooks? // {}) | length) == 0 then del(.hooks) else . end
  ' "$SETTINGS" > "$BASE_SETTINGS"

  SETTINGS_TMP="$(mktemp)"
  jq -s '
    .[0] as $current |
    .[1] as $selected |
    ($current * ($selected | del(.hooks))) |
    if $selected.hooks? then
      .hooks.Notification = (
        ($current.hooks.Notification // []) + ($selected.hooks.Notification // [])
      ) |
      .hooks.Stop = (
        ($current.hooks.Stop // []) + ($selected.hooks.Stop // [])
      )
    else . end
  ' "$BASE_SETTINGS" "$SELECTED_SETTINGS" > "$SETTINGS_TMP"
  mv "$SETTINGS_TMP" "$SETTINGS"
  SETTINGS_TMP=""
  if [ "$BASE_SETTINGS" != "$SETTINGS" ]; then
    rm -f "$BASE_SETTINGS"
  fi
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
  --arg installed_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --argjson notifications "$INSTALL_NOTIFICATION_ENHANCEMENTS" '
    .installedAt = $installed_at |
    .settings.statusLines = true |
    .settings.notificationEnhancements = $notifications
  ' "$WORK_MANIFEST" > "$manifest_tmp"
mv "$manifest_tmp" "$WORK_MANIFEST"
mv "$WORK_MANIFEST" "$MANIFEST"
WORK_MANIFEST=""
echo "saved uninstall manifest -> ${MANIFEST}"

echo "done. Restart Claude Code (or start a new session) to pick up the changes."
