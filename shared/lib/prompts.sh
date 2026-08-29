#!/bin/bash

# Interactive prompt helpers. Installers can fall back to defaults when there
# is no terminal; uninstallers call prompt_open with "required" instead.

PROMPT_FD=""

prompt_open() {
  local mode="${1:-optional}"

  if { exec 3<>/dev/tty; } 2>/dev/null; then
    PROMPT_FD=3
    return 0
  fi

  PROMPT_FD=""
  if [ "$mode" = "required" ]; then
    echo "error: this operation requires an interactive terminal" >&2
    return 1
  fi
}

prompt_close() {
  if [ -n "$PROMPT_FD" ]; then
    exec 3>&-
    PROMPT_FD=""
  fi
}

ask_yes_no() {
  local question="$1"
  local default_answer="${2:-yes}"
  local suffix
  local answer

  if [ -z "$PROMPT_FD" ]; then
    [ "$default_answer" = "yes" ]
    return
  fi

  if [ "$default_answer" = "yes" ]; then
    suffix="[Y/n]"
  else
    suffix="[y/N]"
  fi

  while true; do
    printf '%s %s ' "$question" "$suffix" >&"$PROMPT_FD"
    if ! IFS= read -r answer <&"$PROMPT_FD"; then
      printf '\n' >&"$PROMPT_FD"
      [ "$default_answer" = "yes" ]
      return
    fi

    case "$answer" in
      "") [ "$default_answer" = "yes" ]; return ;;
      [Yy]|[Yy][Ee][Ss]) return 0 ;;
      [Nn]|[Nn][Oo]) return 1 ;;
      *) printf 'Please answer yes or no.\n' >&"$PROMPT_FD" ;;
    esac
  done
}
