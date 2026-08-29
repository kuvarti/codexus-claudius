#!/bin/bash

sandbox_create() {
  local prefix="$1"
  mktemp -d "/tmp/${prefix}.XXXXXX"
}

sandbox_cleanup() {
  local sandbox_path="$1"
  local prefix="$2"

  case "$sandbox_path" in
    "/tmp/${prefix}."*)
      [ ! -d "$sandbox_path" ] || rm -rf "$sandbox_path"
      ;;
    *)
      echo "warning: refused to clean unexpected sandbox path: ${sandbox_path}" >&2
      ;;
  esac
}

sandbox_print_tree() {
  local sandbox_path="$1"

  if [ -z "$(find "$sandbox_path" -mindepth 1 -print -quit)" ]; then
    echo "  (empty)"
  else
    (
      cd "$sandbox_path"
      find . -mindepth 1 -maxdepth 6 -printf '  %P\n' | sort
    )
  fi
}
