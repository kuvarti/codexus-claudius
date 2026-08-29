#!/bin/bash

# Managed-file operations shared by both providers. Callers set REPO_DIR,
# STATE_DIR, WORK_MANIFEST and HAS_MANIFEST before invoking these functions.

managed_file_install() {
  local source_rel="$1"
  local target="$2"
  local component="$3"
  local backup_name="$4"
  local source="${REPO_DIR}/${source_rel}"
  local backup_rel=""
  local checksum

  [ -f "$source" ] || {
    echo "error: source file not found: ${source}" >&2
    return 1
  }
  mkdir -p "$(dirname "$target")"

  if jq -e --arg path "$target" '.files[$path] != null' "$WORK_MANIFEST" >/dev/null; then
    backup_rel="$(jq -r --arg path "$target" '.files[$path].backup // ""' "$WORK_MANIFEST")"
  elif [ -e "$target" ] || [ -L "$target" ]; then
    backup_rel="backups/${backup_name}"
    cp -p "$target" "${STATE_DIR}/${backup_rel}"
    echo "backed up existing file -> ${STATE_DIR}/${backup_rel}"
  fi

  cp "$source" "$target"
  checksum="$(sha256_file "$target")"
  manifest_put_file "$target" "$component" "$source_rel" "$checksum" "$backup_rel"
}

managed_file_remove() {
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
    expected_checksum="$(sha256_file "$source")"
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
    $HAS_MANIFEST && manifest_remove_file "$target"
    return 0
  fi

  current_checksum="$(sha256_file "$target")"
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
  $HAS_MANIFEST && manifest_remove_file "$target"
}

managed_component_remove() {
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
    managed_file_remove "$target" "$source_rel" "$label"
  done
}
