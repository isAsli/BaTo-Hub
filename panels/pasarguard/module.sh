#!/usr/bin/env bash
set -euo pipefail

. /opt/batohub/lib/common.sh

PANEL_DIR="${INSTALL_DIR}/panels"
PANEL_NAME="pasarguard"
PANEL_PATH="${PASARGUARD_DIR:-/opt/pasarguard}"

panel_detect() {
  if [ -d "$PANEL_PATH" ] && [ -f "$PANEL_PATH/.env" ] && [ -x "$PANEL_PATH/pasarguard" ]; then
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
  printf 'not_implemented'
}

panel_status() {
  if panel_detect; then
    printf '%s\n' "not_implemented"
  else
    printf '%s\n' "not_installed"
  fi
}

panel_install() {
  err "PasarGuard installation is not handled by BaToHub."
  return 1
}

panel_uninstall() {
  err "BaToHub does not remove the panel itself."
  return 1
}

panel_ssl_issue() {
  err "SSL issuance is not implemented for PasarGuard in this release."
  return 1
}

panel_ssl_renew() {
  err "SSL renewal is not implemented for PasarGuard in this release."
  return 1
}

panel_ssl_status() {
  err "SSL status is not implemented for PasarGuard in this release."
  return 1
}

panel_ssl_remove() {
  err "SSL removal is not implemented for PasarGuard in this release."
  return 1
}

panel_template_apply() {
  err "Template application is not implemented for PasarGuard in this release."
  return 1
}

panel_template_remove() {
  err "Template removal is not implemented for PasarGuard in this release."
  return 1
}

panel_logs() {
  err "Panel logs are not implemented for PasarGuard in this release."
  return 1
}

panel_update() {
  err "Panel update is not implemented for PasarGuard in this release."
  return 1
}

panel_menu() {
  clear
  banner 'PasarGuard'
  printf '%s\n' '----------------------------------------'
  printf '%s\n' 'Not implemented in this release.'
  printf '%s\n' 'This panel is reserved for a future version of BaToHub.'
  pause
}
