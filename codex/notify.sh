#!/bin/bash
# Codex passes one JSON payload argument to the configured notify command.
# Accept stdin too so the script is easy to test in isolation.
set -u

if [ "$#" -gt 0 ]; then
  payload="$1"
elif [ ! -t 0 ]; then
  payload="$(cat)"
else
  payload="{}"
fi

if ! printf '%s' "$payload" | jq -e . >/dev/null 2>&1; then
  payload="{}"
fi

event="$(printf '%s' "$payload" | jq -r '.type // .event // "agent-turn-complete"')"
cwd="$(printf '%s' "$payload" | jq -r '.cwd // ""')"
project="$(basename "${cwd:-Codex}")"
[ -n "$project" ] || project="Codex"

message="$(printf '%s' "$payload" | jq -r '
  (."last-assistant-message" // .last_assistant_message // .message // "") |
  tostring |
  gsub("[\\r\\n]+"; " ") |
  if length > 240 then .[0:237] + "..." else . end
')"

case "$event" in
  *approval*)
    title="Codex — ${project}"
    [ -n "$message" ] || message="Codex needs your approval."
    sound="minecraft-villager-huh-sound-effect.mp3"
    ;;
  *)
    title="Codex — ${project}"
    [ -n "$message" ] || message="Turn completed."
    sound="cartoon-eating-sound-effect.mp3"
    ;;
esac

command -v notify-send >/dev/null 2>&1 && notify-send "$title" "$message" >/dev/null 2>&1 || true

sound_path="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/sounds/${sound}"
if command -v ffplay >/dev/null 2>&1 && [ -f "$sound_path" ]; then
  ffplay -nodisp -autoexit -loglevel quiet "$sound_path" >/dev/null 2>&1 &
fi

exit 0
