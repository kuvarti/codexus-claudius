#!/bin/bash
# Safely removes components installed by claudius-sculptus.
#
# Usage:
#   ./uninstall.sh   (from a local checkout)
#   curl -fsSL https://raw.githubusercontent.com/kuvarti/claudius-sculptus/master/uninstall.sh | bash
set -euo pipefail

REPO_URL="https://github.com/kuvarti/claudius-sculptus.git"
CLAUDE_DIR="${CLAUDIUS_SCULPTUS_TARGET_DIR:-${HOME}/.claude}"
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

command -v jq >/dev/null || { echo "error: jq is required" >&2; exit 1; }
command -v sha256sum >/dev/null || { echo "error: sha256sum is required" >&2; exit 1; }

# Uninstall is destructive, so unlike install it requires an interactive
# terminal and never silently accepts defaults in CI or another headless shell.
if ! { exec 3<>/dev/tty; } 2>/dev/null; then
  echo "error: uninstall requires an interactive terminal" >&2
  exit 1
fi
PROMPT_FD=3

ask_yes_no() {
  local question="$1"
  local default_answer="$2"
  local suffix
  local answer

  if [ "$default_answer" = "yes" ]; then
    suffix="[Y/n]"
  else
    suffix="[y/N]"
  fi

  while true; do
    printf '%s %s ' "$question" "$suffix" >&"$PROMPT_FD"
    if ! IFS= read -r answer <&"$PROMPT_FD"; then
      printf '\nerror: unable to read confirmation\n' >&2
      exit 1
    fi

    case "$answer" in
      "")
        [ "$default_answer" = "yes" ]
        return
        ;;
      [Yy]|[Yy][Ee][Ss]) return 0 ;;
      [Nn]|[Nn][Oo]) return 1 ;;
      *) printf 'Please answer yes or no.\n' >&"$PROMPT_FD" ;;
    esac
  done
}

echo "Choose which claudius-sculptus components to remove:"

REMOVE_STATUS_LINES=false
if ask_yes_no "Remove custom status lines?" "yes"; then
  REMOVE_STATUS_LINES=true
fi

REMOVE_NOTIFICATION_ENHANCEMENTS=false
if ask_yes_no "Remove desktop notification and sound enhancements?" "yes"; then
  REMOVE_NOTIFICATION_ENHANCEMENTS=true
fi

REMOVE_GLOBAL_CLAUDE=false
if ask_yes_no "Remove the global CLAUDE.md file?" "no"; then
  REMOVE_GLOBAL_CLAUDE=true
fi

REMOVE_INIT_COMMAND=false
if ask_yes_no "Remove the custom /init command?" "yes"; then
  REMOVE_INIT_COMMAND=true
fi

if ! $REMOVE_STATUS_LINES &&
   ! $REMOVE_NOTIFICATION_ENHANCEMENTS &&
   ! $REMOVE_GLOBAL_CLAUDE &&
   ! $REMOVE_INIT_COMMAND; then
  echo "nothing selected; uninstall cancelled"
  exec 3>&-
  exit 0
fi

echo
echo "Selected for removal:"
$REMOVE_STATUS_LINES && echo "  - custom status lines"
$REMOVE_NOTIFICATION_ENHANCEMENTS && echo "  - desktop notification and sound enhancements"
$REMOVE_GLOBAL_CLAUDE && echo "  - global CLAUDE.md"
$REMOVE_INIT_COMMAND && echo "  - custom /init command"
echo

if ! ask_yes_no "Proceed with uninstall?" "no"; then
  echo "uninstall cancelled"
  exec 3>&-
  exit 0
fi
exec 3>&-

# Use local sources when available; otherwise clone them so exact checksums and
# managed settings can still be identified during a curl-based uninstall.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || true)"
if [ -n "${SCRIPT_DIR:-}" ] && [ -f "${SCRIPT_DIR}/settings.snippet.json" ]; then
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

HAS_MANIFEST=false
if [ -f "$MANIFEST" ]; then
  jq -e '
    .schemaVersion == 1 and
    (.files | type == "object") and
    (.settings | type == "object")
  ' "$MANIFEST" >/dev/null || {
    echo "error: ${MANIFEST} is invalid; refusing unsafe uninstall" >&2
    exit 1
  }
  HAS_MANIFEST=true
  WORK_MANIFEST="$(mktemp "${STATE_DIR}/uninstall-manifest.XXXXXX")"
  cp "$MANIFEST" "$WORK_MANIFEST"
else
  echo "warning: no install manifest found; only exact source matches will be removed" >&2
fi

remove_manifest_record() {
  local target="$1"
  local manifest_tmp

  $HAS_MANIFEST || return 0
  manifest_tmp="$(mktemp "${STATE_DIR}/manifest-update.XXXXXX")"
  jq --arg path "$target" 'del(.files[$path])' "$WORK_MANIFEST" > "$manifest_tmp"
  mv "$manifest_tmp" "$WORK_MANIFEST"
}

remove_managed_file() {
  local target="$1"
  local source_rel="$2"
  local label="$3"
  local source="${REPO_DIR}/${source_rel}"
  local expected_checksum=""
  local backup_rel=""
  local backup_path=""
  local current_checksum

  if $HAS_MANIFEST && jq -e --arg path "$target" '.files[$path] != null' "$WORK_MANIFEST" >/dev/null; then
    expected_checksum="$(jq -r --arg path "$target" '.files[$path].sha256 // ""' "$WORK_MANIFEST")"
    backup_rel="$(jq -r --arg path "$target" '.files[$path].backup // ""' "$WORK_MANIFEST")"
  elif ! $HAS_MANIFEST && [ -f "$source" ]; then
    expected_checksum="$(sha256sum "$source" | awk '{print $1}')"
  else
    return 0
  fi

  if [ -n "$backup_rel" ]; then
    backup_path="${STATE_DIR}/${backup_rel}"
    if [ ! -f "$backup_path" ]; then
      echo "warning: backup is missing; left ${label} unchanged -> ${target}" >&2
      return 0
    fi
  fi

  if [ -L "$target" ]; then
    echo "warning: left symbolic link unchanged -> ${target}" >&2
    return 0
  fi

  if [ ! -e "$target" ]; then
    if [ -n "$backup_path" ]; then
      mkdir -p "$(dirname "$target")"
      cp -p "$backup_path" "$target"
      rm -f "$backup_path"
      echo "restored original ${label} -> ${target}"
    else
      echo "already absent -> ${target}"
    fi
    remove_manifest_record "$target"
    return 0
  fi

  current_checksum="$(sha256sum "$target" | awk '{print $1}')"
  if [ -z "$expected_checksum" ] || [ "$current_checksum" != "$expected_checksum" ]; then
    echo "warning: left modified ${label} in place -> ${target}" >&2
    return 0
  fi

  if [ -n "$backup_path" ]; then
    cp -p "$backup_path" "$target"
    rm -f "$backup_path"
    echo "restored original ${label} -> ${target}"
  else
    rm -f "$target"
    echo "removed ${label} -> ${target}"
  fi
  remove_manifest_record "$target"
}

remove_manifest_component() {
  local component="$1"
  local target
  local source_rel
  local label
  local -a targets=()

  mapfile -t targets < <(
    jq -r --arg component "$component" '
      .files |
      to_entries[] |
      select(.value.component == $component) |
      .key
    ' "$WORK_MANIFEST"
  )

  for target in "${targets[@]}"; do
    source_rel="$(jq -r --arg path "$target" '.files[$path].source // ""' "$WORK_MANIFEST")"
    label="$(basename "$target")"
    remove_managed_file "$target" "$source_rel" "$label"
  done
}

if $REMOVE_STATUS_LINES; then
  if $HAS_MANIFEST; then
    remove_manifest_component "status_lines"
  else
    remove_managed_file "${CLAUDE_DIR}/statusline-command.sh" "statusline-command.sh" "statusline-command.sh"
    remove_managed_file "${CLAUDE_DIR}/subagent-statusline.sh" "subagent-statusline.sh" "subagent-statusline.sh"
  fi
fi

if $REMOVE_NOTIFICATION_ENHANCEMENTS; then
  if $HAS_MANIFEST; then
    remove_manifest_component "notification_enhancements"
  else
    for sound in "${REPO_DIR}/media/"*.mp3; do
      [ -f "$sound" ] || continue
      sound_name="$(basename "$sound")"
      remove_managed_file \
        "${CLAUDE_DIR}/sounds/${sound_name}" \
        "media/${sound_name}" \
        "$sound_name"
    done
  fi
fi

if $REMOVE_GLOBAL_CLAUDE; then
  if $HAS_MANIFEST; then
    remove_manifest_component "global_claude"
  else
    remove_managed_file "${CLAUDE_DIR}/CLAUDE.md" "global-CLAUDE.md" "global CLAUDE.md"
  fi
fi

if $REMOVE_INIT_COMMAND; then
  if $HAS_MANIFEST; then
    remove_manifest_component "init_command"
  else
    remove_managed_file "${CLAUDE_DIR}/commands/init.md" "commands/init.md" "custom /init command"
  fi
fi

# Remove only settings whose complete values or commands match this project.
# User-defined status lines and unrelated hooks are preserved.
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
      if (.settings | has("fileExisted")) then
        .settings.fileExisted
      else true end
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
    --slurpfile managed "${REPO_DIR}/settings.snippet.json" '
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

      if $remove_status and .statusLine == $managed[0].statusLine then
        if $original_status_present then
          .statusLine = $original_status
        else del(.statusLine) end
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
      if ((.hooks.Notification? // []) | length) == 0 then
        del(.hooks.Notification)
      else . end |
      if ((.hooks.Stop? // []) | length) == 0 then
        del(.hooks.Stop)
      else . end |
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
    ([
      .settings.statusLines,
      .settings.notificationEnhancements
    ] | map(select(. == true)) | length)
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
