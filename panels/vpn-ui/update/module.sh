#!/usr/bin/env bash
set -Eeuo pipefail

# VPN-UI update through the official VPN-UI deployment script.

panel_update_impl() {
  need_root || return 1
  local before after
  before="$(panel_version)"
  printf 'VPN-UI version before the update: %s\n' "$before"
  if ! panel_fetch_official_installer "$VPNUI_DEPLOY_URL" ""; then
    err "The VPN-UI updater did not complete. Full output: ${LOG_FILE}"
    return 1
  fi
  after="$(panel_version)"
  printf 'VPN-UI version after the update: %s\n' "$after"
  if [[ "$before" == "$after" ]]; then
    warn "The reported version did not change. Check the installer output in ${LOG_FILE}."
  else
    ok "VPN-UI updated from ${before} to ${after}."
  fi
  return 0
}
