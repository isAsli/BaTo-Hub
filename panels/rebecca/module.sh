#!/usr/bin/env bash
set -euo pipefail

. /opt/batohub/lib/common.sh

PANEL_DIR="${INSTALL_DIR}/panels"
PANEL_NAME="rebecca"
PANEL_PATH="${REBECCA_DIR:-/opt/rebecca}"

panel_detect() {
  if [ -d "$PANEL_PATH" ] && [ -f "$PANEL_PATH/.env" ] && [ -f "$PANEL_PATH/Rebecca" ]; then
    return 0
  fi
  return 1
}

panel_detect_path() {
  if panel_detect; then
    printf '%s' "$PANEL_PATH"
    return 0
  fi
  printf ''
  return 1
}

panel_version() {
  local binary="$PANEL_PATH/Rebecca"
  if [ -x "$binary" ]; then
    "$binary" --version 2>/dev/null | sed -n '1p' | tr -d '[:space:]' || true
  else
    printf 'unknown'
  fi
}

panel_status() {
  if ! panel_detect; then
    printf '%s\n' "not_installed"
    return 0
  fi
  if command -v systemctl >/dev/null 2>&1; then
    if systemctl is-active "$SERVICE_NAME" >/dev/null 2>&1; then
      printf '%s\n' "running"
      return 0
    fi
  fi
  printf '%s\n' "stopped"
}

panel_install() {
  err "Panel install is not handled by BaToHub."
  return 1
}

panel_uninstall() {
  err "BaToHub does not remove the panel itself."
  return 1
}

panel_ssl_issue() {
  . "${PANEL_DIR}/${PANEL_NAME}/ssl/module.sh"
  ssl_install
}

panel_ssl_renew() {
  . "${PANEL_DIR}/${PANEL_NAME}/ssl/module.sh"
  ssl_renew
}

panel_ssl_status() {
  . "${PANEL_DIR}/${PANEL_NAME}/ssl/module.sh"
  ssl_status
}

panel_ssl_remove() {
  . "${PANEL_DIR}/${PANEL_NAME}/ssl/module.sh"
  ssl_remove
}

panel_template_apply() {
  . "${PANEL_DIR}/${PANEL_NAME}/templates/module.sh"
  template_apply
}

panel_template_remove() {
  . "${PANEL_DIR}/${PANEL_NAME}/templates/module.sh"
  template_remove
}

panel_logs() {
  local log_dir="$LOG_DIR"
  if [ -f "$log_dir/batohub.log" ]; then
    tail -n 120 "$log_dir/batohub.log" | grep -iE 'rebecca|ssl|template|certbot|letsencrypt' || true
  else
    err "Log file not found."
  fi
}

panel_update() {
  . "${PANEL_DIR}/${PANEL_NAME}/update/module.sh"
  panel_update "$@"
}

panel_menu() {
  . "${PANEL_DIR}/${PANEL_NAME}/menu/module.sh"
  panel_menu "$@"
}
