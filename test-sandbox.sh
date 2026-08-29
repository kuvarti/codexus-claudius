#!/bin/bash
# Runs install/uninstall experiments against an isolated temporary directory.
# The real ~/.claude directory is never used.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ ! -t 0 ]; then
  echo "error: the test sandbox requires an interactive terminal" >&2
  exit 1
fi

command -v jq >/dev/null || { echo "error: jq is required" >&2; exit 1; }

SANDBOX_DIR="$(mktemp -d /tmp/claudius-sculptus-sandbox.XXXXXX)"

cleanup() {
  case "$SANDBOX_DIR" in
    /tmp/claudius-sculptus-sandbox.*)
      [ ! -d "$SANDBOX_DIR" ] || rm -rf "$SANDBOX_DIR"
      ;;
    *)
      echo "warning: refused to clean unexpected sandbox path: ${SANDBOX_DIR}" >&2
      ;;
  esac
}
trap cleanup EXIT
trap 'exit 130' INT TERM

run_installer() {
  echo
  CLAUDIUS_SCULPTUS_TARGET_DIR="$SANDBOX_DIR" "${SCRIPT_DIR}/install.sh"
}

run_uninstaller() {
  echo
  CLAUDIUS_SCULPTUS_TARGET_DIR="$SANDBOX_DIR" "${SCRIPT_DIR}/uninstall.sh"
}

inspect_sandbox() {
  echo
  echo "Sandbox files:"
  if [ -z "$(find "$SANDBOX_DIR" -mindepth 1 -print -quit)" ]; then
    echo "  (empty)"
  else
    (
      cd "$SANDBOX_DIR"
      find . -mindepth 1 -maxdepth 4 -printf '  %P\n' | sort
    )
  fi

  if [ -f "$SANDBOX_DIR/settings.json" ]; then
    echo
    echo "settings.json:"
    jq . "$SANDBOX_DIR/settings.json"
  fi

  if [ -f "$SANDBOX_DIR/.claudius-sculptus/manifest.json" ]; then
    echo
    echo "manifest.json:"
    jq . "$SANDBOX_DIR/.claudius-sculptus/manifest.json"
  fi
}

simulate_modification() {
  echo
  if [ ! -f "$SANDBOX_DIR/statusline-command.sh" ]; then
    echo "Install the components first; no sandbox status-line file exists yet."
    return
  fi

  printf '\n# modified inside the safe test sandbox\n' >> "$SANDBOX_DIR/statusline-command.sh"
  echo "modified sandbox file -> ${SANDBOX_DIR}/statusline-command.sh"
  echo "The uninstaller should now warn and leave this file in place."
}

echo "claudius-sculptus safe test sandbox"
echo "Temporary target: ${SANDBOX_DIR}"
echo "Your real ~/.claude directory will not be touched."

while true; do
  echo
  echo "1) Run installer"
  echo "2) Inspect sandbox files"
  echo "3) Simulate a user-modified installed file"
  echo "4) Run uninstaller"
  echo "5) Exit and delete sandbox"
  printf 'Choose an option [1-5]: '
  IFS= read -r choice

  case "$choice" in
    1) run_installer ;;
    2) inspect_sandbox ;;
    3) simulate_modification ;;
    4) run_uninstaller ;;
    5)
      echo "deleting temporary sandbox"
      exit 0
      ;;
    *) echo "Please choose a number from 1 to 5." ;;
  esac
done
