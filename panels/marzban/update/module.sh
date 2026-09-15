#!/usr/bin/env bash
set -Eeuo pipefail

# Marzban update. The official script performs the upgrade; BaToHub reports the
# version before and after so the result is visible rather than assumed.

panel_update_impl() {
  need_root || return 1
  local before after
  before="$(panel_version)"
  printf 'Marzban version before the update: %s\n' "$before"
  if ! panel_fetch_official_installer "$MARZBAN_SCRIPT_URL" upgrade; then
    err "The Marzban updater did not complete. Full output: ${LOG_FILE}"
    return 1
  fi
  after="$(panel_version)"
  printf 'Marzban version after the update: %s\n' "$after"
  if [[ "$before" == "$after" ]]; then
    warn "The reported version did not change. Check the installer output in ${LOG_FILE}."
  else
    ok "Marzban updated from ${before} to ${after}."
  fi
  return 0
}
