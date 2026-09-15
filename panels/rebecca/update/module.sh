#!/usr/bin/env bash
set -Eeuo pipefail

# Rebecca update.
#
# The update is delegated to the official Rebecca installer. The current version
# is printed before and after the operation so the result is visible instead of
# assumed.

panel_update_impl() {
  need_root || return 1
  local before after
  before="$(panel_version)"
  printf 'Rebecca version before the update: %s\n' "$before"
  if ! panel_fetch_official_installer "$REBECCA_INSTALLER_URL" update; then
    err "The Rebecca updater did not complete. Full output: ${LOG_FILE}"
    return 1
  fi
  after="$(panel_version)"
  printf 'Rebecca version after the update: %s\n' "$after"
  if [[ "$before" == "$after" ]]; then
    warn "The reported version did not change. Check the installer output in ${LOG_FILE}."
  else
    ok "Rebecca updated from ${before} to ${after}."
  fi
  return 0
}
