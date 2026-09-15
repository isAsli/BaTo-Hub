#!/usr/bin/env bash
set -Eeuo pipefail

# 3X-UI update through the official 3X-UI installer.

panel_update_impl() {
  need_root || return 1
  local before after
  before="$(panel_version)"
  printf '3X-UI version before the update: %s\n' "$before"
  if ! panel_fetch_official_installer "$XUI_INSTALLER_URL" ""; then
    err "The 3X-UI updater did not complete. Full output: ${LOG_FILE}"
    return 1
  fi
  after="$(panel_version)"
  printf '3X-UI version after the update: %s\n' "$after"
  if [[ "$before" == "$after" ]]; then
    warn "The reported version did not change. Check the installer output in ${LOG_FILE}."
  else
    ok "3X-UI updated from ${before} to ${after}."
  fi
  return 0
}
