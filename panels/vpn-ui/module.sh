#!/usr/bin/env bash
set -Eeuo pipefail

# VPN-UI panel module.
#
# VPN-UI is a fork of 3X-UI but is a separate installation: it lives under
# /opt/vpn-ui, is started by the vpn-ui service, and ships its own uninstaller.
# Nothing here assumes 3X-UI paths.

VPNUI_DEPLOY_URL="${VPNUI_DEPLOY_URL:-https://raw.githubusercontent.com/Sir-MmD/vpn-ui/main/deploy.sh}"
VPNUI_REPO_URL="${VPNUI_REPO_URL:-https://github.com/Sir-MmD/vpn-ui}"

vpnui_binary() {
  local candidate architecture
  architecture="$(uname -m)"
  for candidate in "${PANEL_PATH}/vpn-ui-${architecture}" "${PANEL_PATH}/vpn-ui-amd64" "${PANEL_PATH}/vpn-ui-arm64"; do
    if [[ -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

panel_detect() {
  [[ -d "$PANEL_PATH" ]] && return 0
  service_registered "$PANEL_SERVICE" && return 0
  port_in_use "$PANEL_PORT" && return 0
  return 1
}

panel_version() {
  local version="" binary
  if binary="$(vpnui_binary)"; then
    version="$("$binary" --version 2>/dev/null | head -n 1 | tr -d '\r' || true)"
  fi
  printf '%s\n' "${version:-unknown}"
}

panel_status() {
  if ! panel_detect; then
    printf '%s\n' not_installed
    return 0
  fi
  if service_active "$PANEL_SERVICE"; then
    printf '%s\n' running
    return 0
  fi
  printf '%s\n' stopped
}

# --- Version selection ------------------------------------------------------
#
# The official VPN-UI deployment script resolves the newest release itself and
# accepts no version argument. BaToHub therefore reports the published versions
# for information and refuses a pinned install instead of ignoring the request.

panel_available_versions() { panel_versions_available "${1:-5}"; }

panel_install_version() {
  local version="${1:-}" latest
  panel_valid_version_string "$version" || return 1
  latest="$(panel_latest_stable_version)" || latest=""
  if [[ -z "$latest" || "$version" != "$latest" ]]; then
    panel_version_pinning_unsupported "$version"
    return 1
  fi
  printf 'The VPN-UI deployment script installs the newest release, which is %s.\n' "$latest"
  panel_install
}

panel_install() {
  need_root || return 1
  printf 'VPN-UI is installed with its official deployment script.\n'
  printf 'Source: %s\n\n' "$VPNUI_REPO_URL"
  if ! panel_fetch_official_installer "$VPNUI_DEPLOY_URL" ""; then
    err "The VPN-UI deployment script did not complete. Full output: ${LOG_FILE}"
    return 1
  fi
  ok "VPN-UI deployment finished."
}

panel_uninstall() {
  need_root || return 1
  printf 'BaToHub does not remove VPN-UI. Panel files: %s, database: /opt/vpn-ui/vpn-ui.db\n' "$PANEL_PATH"
  printf 'VPN-UI ships its own uninstaller; use that to remove the panel itself.\n\n'
  printf 'BaToHub-managed changes for VPN-UI are:\n'
  printf '  staged templates: %s\n' "$PANEL_TEMPLATE_DIR"
  printf '  certificates: %s\n' "$PANEL_SSL_DIR"
  if ! ui_confirm_phrase REMOVE 'Remove these BaToHub-managed changes?'; then
    printf 'Nothing was removed.\n'
    return 0
  fi
  panel_template_remove || true
  panel_ssl_remove || true
  ok "BaToHub-managed VPN-UI changes were removed. The panel itself and its database are untouched."
}

panel_update() { panel_submodule update && panel_update_impl; }

panel_logs() { panel_logs_generic "$PANEL_SERVICE" "$PANEL_PATH"; }

panel_ssl_issue() { panel_submodule ssl && ssl_issue; }
panel_ssl_renew() { panel_submodule ssl && ssl_renew; }
panel_ssl_status() { panel_submodule ssl && ssl_status; }
panel_ssl_remove() { panel_submodule ssl && ssl_remove; }
panel_template_apply() { panel_submodule templates && template_apply; }
panel_template_remove() { panel_submodule templates && template_remove; }
panel_template_status() { panel_submodule templates && template_status; }
panel_menu() { panel_submodule menu && panel_menu_impl; }
