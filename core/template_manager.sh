#!/usr/bin/env bash
set -euo pipefail

. /opt/batohub/lib/common.sh

template_menu_for_panel() {
  local panel="$1"
  local panel_dir
  panel_dir=$(panel_detect_path "$panel")
  if [ -z "$panel_dir" ] || [ ! -f "${PANEL_DIR}/${panel}/templates/module.sh" ]; then
    err "Template module not available for this panel."
    pause
    return
  fi
  . "${PANEL_DIR}/${panel}/templates/module.sh"
  template_menu
}

apply_panel_template() {
  local panel="$1"
  local panel_dir
  panel_dir=$(panel_detect_path "$panel")
  if [ -z "$panel_dir" ]; then
    err "Panel not detected."
    return 1
  fi
  if [ ! -f "${PANEL_DIR}/${panel}/templates/module.sh" ]; then
    err "Template module not available for this panel."
    return 1
  fi
  . "${PANEL_DIR}/${panel}/templates/module.sh"
  template_apply "$@"
}

remove_panel_template() {
  local panel="$1"
  local panel_dir
  panel_dir=$(panel_detect_path "$panel")
  if [ -z "$panel_dir" ]; then
    err "Panel not detected."
    return 1
  fi
  if [ ! -f "${PANEL_DIR}/${panel}/templates/module.sh" ]; then
    err "Template module not available for this panel."
    return 1
  fi
  . "${PANEL_DIR}/${panel}/templates/module.sh"
  template_remove "$@"
}
