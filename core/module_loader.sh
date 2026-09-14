#!/usr/bin/env bash
set -euo pipefail

MODULE_DIR="${INSTALL_DIR}/modules"
MODULE_CACHE=()

load_module_list() {
  MODULE_CACHE=()
  if [ ! -d "$MODULE_DIR" ]; then
    return 0
  fi
  for json in "$MODULE_DIR"/*/module.json; do
    if [ -f "$json" ]; then
      MODULE_CACHE+=("$json")
    fi
  done
}

get_module_name() {
  local json="$1"
  json_get "$json" "name"
}

get_module_status() {
  local json="$1"
  local status
  status=$(json_get "$json" "status")
  if [ "$status" = "active" ]; then
    printf '%s' 'active'
  else
    printf '%s' 'disabled'
  fi
}

load_active_module_script() {
  local json="$1"
  local entry
  entry=$(json_get "$json" "entry")
  if [ -z "$entry" ] || [ ! -f "$entry" ]; then
    return 1
  fi
  . "$entry"
  return 0
}

module_is_active() {
  local json="$1"
  [ "$(get_module_status "$json")" = "active" ]
}

active_module_list() {
  load_module_list
  local json
  for json in "${MODULE_CACHE[@]}"; do
    if module_is_active "$json"; then
      printf '%s\n' "$json"
    fi
  done
}
