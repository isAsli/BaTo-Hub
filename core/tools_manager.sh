#!/usr/bin/env bash
set -Eeuo pipefail

# Tool menu. Tools are optional helpers that are not tied to a single panel.

tool_state_of() {
  local name="$1"
  (tool_load "$name" && tool_status) 2>/dev/null | tail -n 1
}

tool_version_of() {
  local name="$1"
  (tool_load "$name" && tool_version) 2>/dev/null | tail -n 1
}

tools_menu() {
  local choice name names=() index=0 state
  while IFS= read -r name; do
    [[ -n "$name" ]] && names+=("$name")
  done < <(loader_tools)
  if [[ "${#names[@]}" -eq 0 ]]; then
    ui_title "Tools"
    warn "No tools are shipped in this release."
    pause
    return 0
  fi
  ui_title "Tools"
  for name in "${names[@]}"; do
    index=$((index + 1))
    state="$(tool_state_of "$name")"
    printf '%s) %-14s %-14s %s\n' "$index" "$(json_get "${TOOL_DIR}/${name}/tool.json" display_name)" \
      "$(panel_status_text "$state")" "version $(tool_version_of "$name")"
  done
  printf '0) Back\n'
  choice="$(ui_menu_choice)"
  [[ "$choice" =~ ^[0-9]+$ ]] || {
    warn "Invalid selection."
    return 0
  }
  [[ "$choice" == 0 ]] && return 0
  name="${names[$((choice - 1))]:-}"
  [[ -n "$name" ]] || {
    warn "Invalid selection."
    return 0
  }
  tool_load "$name" || return 1
  tool_menu
}
