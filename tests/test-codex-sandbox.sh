#!/bin/bash
# Runs Codex install/uninstall experiments against isolated temporary paths.
# The real ~/.codex and ~/.agents directories are never used.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=tests/sandbox-common.sh
source "${SCRIPT_DIR}/tests/sandbox-common.sh"

if [ ! -t 0 ]; then
  echo "error: the test sandbox requires an interactive terminal" >&2
  exit 1
fi

command -v jq >/dev/null || { echo "error: jq is required" >&2; exit 1; }
command -v python3 >/dev/null || { echo "error: python3 is required" >&2; exit 1; }

SANDBOX_PREFIX="claudius-sculptus-codex-sandbox"
SANDBOX_DIR="$(sandbox_create "$SANDBOX_PREFIX")"
CODEX_SANDBOX="${SANDBOX_DIR}/.codex"
SKILLS_SANDBOX="${SANDBOX_DIR}/.agents/skills"

cleanup() {
  sandbox_cleanup "$SANDBOX_DIR" "$SANDBOX_PREFIX"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

run_installer() {
  echo
  CLAUDIUS_SCULPTUS_CODEX_TARGET_DIR="$CODEX_SANDBOX" \
  CLAUDIUS_SCULPTUS_SKILLS_TARGET_DIR="$SKILLS_SANDBOX" \
    "${SCRIPT_DIR}/install-codex.sh"
}

run_uninstaller() {
  echo
  CLAUDIUS_SCULPTUS_CODEX_TARGET_DIR="$CODEX_SANDBOX" \
  CLAUDIUS_SCULPTUS_SKILLS_TARGET_DIR="$SKILLS_SANDBOX" \
    "${SCRIPT_DIR}/uninstall-codex.sh"
}

inspect_sandbox() {
  echo
  echo "Sandbox files:"
  sandbox_print_tree "$SANDBOX_DIR"

  if [ -f "$CODEX_SANDBOX/config.toml" ]; then
    echo
    echo "config.toml:"
    sed -n '1,200p' "$CODEX_SANDBOX/config.toml"
  fi

  if [ -f "$CODEX_SANDBOX/.claudius-sculptus/manifest.json" ]; then
    echo
    echo "manifest.json:"
    jq . "$CODEX_SANDBOX/.claudius-sculptus/manifest.json"
  fi
}

simulate_modification() {
  echo
  local notifier="${CODEX_SANDBOX}/claudius-sculptus/notify.sh"
  if [ ! -f "$notifier" ]; then
    echo "Install notification enhancements first; no sandbox notifier exists yet."
    return
  fi

  printf '\n# modified inside the safe test sandbox\n' >> "$notifier"
  echo "modified sandbox file -> ${notifier}"
  echo "The uninstaller should now warn and leave this file in place."
}

echo "claudius-sculptus Codex safe test sandbox"
echo "Temporary root: ${SANDBOX_DIR}"
echo "Your real ~/.codex and ~/.agents directories will not be touched."

while true; do
  echo
  echo "1) Run Codex installer"
  echo "2) Inspect sandbox files"
  echo "3) Simulate a user-modified notifier"
  echo "4) Run Codex uninstaller"
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
