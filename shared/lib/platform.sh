#!/bin/bash

# Small platform helpers shared by the Claude Code and Codex entry points.

require_command() {
  local command_name="$1"
  command -v "$command_name" >/dev/null || {
    echo "error: ${command_name} is required" >&2
    return 1
  }
}

sha256_file() {
  sha256sum "$1" | awk '{print $1}'
}

utc_timestamp() {
  date -u +%Y-%m-%dT%H:%M:%SZ
}

warn_notification_dependencies() {
  command -v notify-send >/dev/null || \
    echo "warning: notify-send not found; desktop notifications won't appear" >&2
  command -v ffplay >/dev/null || \
    echo "warning: ffplay not found; notification sounds won't play (install ffmpeg)" >&2
}
