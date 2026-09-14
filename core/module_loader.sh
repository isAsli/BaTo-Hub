#!/usr/bin/env bash
set -euo pipefail

. /opt/batohub/lib/common.sh

PANEL_DIR="${INSTALL_DIR}/panels"

load_panel_list() {
  PANEL_LIST=()
  if [ ! -d "$PANEL_DIR" ]; then
    return 0
  fi
  for json in "$PANEL_DIR"/*/panel.json; do
    if [ -f "$json" ]; then
      PANEL_LIST+=("$json")
    fi
  done
}

panel_exists() {
  local name="$1"
  local json
  for json in "${PANEL_LIST[@]}"; do
    if [ "$(json_get "$json" "name")" = "$name" ]; then
      return 0
    fi
  done
  return 1
}

panel_json_path() {
  local name="$1"
  local json
  for json in "${PANEL_LIST[@]}"; do
    if [ "$(json_get "$json" "name")" = "$name" ]; then
      printf '%s' "$json"
      return 0
    fi
  done
  return 1
}

panel_display_name() {
  local name="$1"
  local json path
  if ! path=$(panel_json_path "$name"); then
    printf '%s' "$name"
    return 0
  fi
  printf '%s' "$(json_get "$path" "display_name")"
}

panel_version() {
  local name="$1"
  local json path
  if ! path=$(panel_json_path "$name"); then
    printf ''
    return 1
  fi
  printf '%s' "$(json_get "$path" "version")"
}

panel_load_script() {
  local name="$1"
  local json path entry
  if ! path=$(panel_json_path "$name"); then
    return 1
  fi
  entry=$(json_get "$path" "entry")
  if [ -z "$entry" ] || [ ! -f "$entry" ]; then
    return 1
  fi
  . "$entry"
  return 0
}
