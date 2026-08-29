#!/bin/bash

# The caller owns WORK_MANIFEST and STATE_DIR. Keeping manifest mutations here
# gives both providers the same checksum/backup safety model.

manifest_validate_basic() {
  local manifest_path="$1"
  local provider="${2:-}"

  jq -e --arg provider "$provider" '
    .schemaVersion == 1 and
    (.files | type == "object") and
    (.settings | type == "object") and
    ($provider == "" or (.provider // $provider) == $provider)
  ' "$manifest_path" >/dev/null
}

manifest_put_file() {
  local target="$1"
  local component="$2"
  local source_rel="$3"
  local checksum="$4"
  local backup_rel="$5"
  local manifest_tmp

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

manifest_remove_file() {
  local target="$1"
  local manifest_tmp

  manifest_tmp="$(mktemp "${STATE_DIR}/manifest-update.XXXXXX")"
  jq --arg path "$target" 'del(.files[$path])' "$WORK_MANIFEST" > "$manifest_tmp"
  mv "$manifest_tmp" "$WORK_MANIFEST"
}
