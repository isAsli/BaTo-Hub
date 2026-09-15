#!/usr/bin/env bash
set -Eeuo pipefail

# PasarGuard update through the official PasarGuard script.

panel_update_impl() {
  need_root || return 1
  local before after
  before="$(panel_version)"
  printf 'PasarGuard version before the update: %s\n' "$before"
  if ! panel_fetch_official_installer "$PASARGUARD_SCRIPT_URL" update; then
    err "The PasarGuard updater did not complete. Full output: ${LOG_FILE}"
    return 1
  fi
  after="$(panel_version)"
  printf 'PasarGuard version after the update: %s\n' "$after"
  if [[ "$before" == "$after" ]]; then
    warn "The reported version did not change. Check the installer output in ${LOG_FILE}."
  else
    ok "PasarGuard updated from ${before} to ${after}."
  fi
  return 0
}
