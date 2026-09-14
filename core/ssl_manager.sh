#!/usr/bin/env bash
set -euo pipefail

. /opt/batohub/lib/common.sh

ssl_menu_for_panel() {
  local panel="$1"
  local panel_dir
  panel_dir=$(panel_detect_path "$panel")
  if [ -z "$panel_dir" ] || [ ! -f "${PANEL_DIR}/${panel}/ssl/module.sh" ]; then
    err "SSL module not available for this panel."
    pause
    return
  fi
  . "${PANEL_DIR}/${panel}/ssl/module.sh"
  ssl_menu
}

issue_panel_ssl() {
  local panel="$1"
  local panel_dir
  panel_dir=$(panel_detect_path "$panel")
  if [ -z "$panel_dir" ]; then
    err "Panel not detected."
    return 1
  fi
  if [ ! -f "${PANEL_DIR}/${panel}/ssl/module.sh" ]; then
    err "SSL module not available for this panel."
    return 1
  fi
  . "${PANEL_DIR}/${panel}/ssl/module.sh"
  ssl_issue "$@"
}

renew_panel_ssl() {
  local panel="$1"
  local panel_dir
  panel_dir=$(panel_detect_path "$panel")
  if [ -z "$panel_dir" ]; then
    err "Panel not detected."
    return 1
  fi
  if [ ! -f "${PANEL_DIR}/${panel}/ssl/module.sh" ]; then
    err "SSL module not available for this panel."
    return 1
  fi
  . "${PANEL_DIR}/${panel}/ssl/module.sh"
  ssl_renew "$@"
}

status_panel_ssl() {
  local panel="$1"
  local panel_dir
  panel_dir=$(panel_detect_path "$panel")
  if [ -z "$panel_dir" ]; then
    err "Panel not detected."
    return 1
  fi
  if [ ! -f "${PANEL_DIR}/${panel}/ssl/module.sh" ]; then
    err "SSL module not available for this panel."
    return 1
  fi
  . "${PANEL_DIR}/${panel}/ssl/module.sh"
  ssl_status "$@"
}

remove_panel_ssl() {
  local panel="$1"
  local panel_dir
  panel_dir=$(panel_detect_path "$panel")
  if [ -z "$panel_dir" ]; then
    err "Panel not detected."
    return 1
  fi
  if [ ! -f "${PANEL_DIR}/${panel}/ssl/module.sh" ]; then
    err "SSL module not available for this panel."
    return 1
  fi
  . "${PANEL_DIR}/${panel}/ssl/module.sh"
  ssl_remove "$@"
}
