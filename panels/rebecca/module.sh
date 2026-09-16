#!/usr/bin/env bash
set -Eeuo pipefail

# Rebecca panel module.
#
# Paths are taken from panel.json through the loader, so nothing here hard-codes
# another module's location. Rebecca can be installed as a systemd binary under
# /opt/rebecca/bin or as a Docker Compose stack in /opt/rebecca; both are
# detected and reported, and BaToHub never rewrites the compose file.

REBECCA_INSTALLER_URL="${REBECCA_INSTALLER_URL:-https://raw.githubusercontent.com/rebeccapanel/Rebecca/master/scripts/rebecca/rebecca-binary.sh}"
REBECCA_REPO_URL="${REBECCA_REPO_URL:-https://github.com/rebeccapanel/Rebecca}"
REBECCA_TEMPLATE_ROOT="${REBECCA_TEMPLATE_ROOT:-/opt/rebecca/bato-templates}"

rebecca_cli_path() {
  local candidate
  for candidate in "/usr/local/bin/rebecca-cli" "${PANEL_PATH}/bin/rebecca-cli" "${PANEL_CLI}"; do
    if [[ -n "$candidate" && -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

# Always returns success: callers assign the result directly, and a failing
# command substitution would abort them under `set -e`.
rebecca_compose_file() {
  if [[ -f "${PANEL_PATH}/docker-compose.yml" ]]; then
    printf '%s\n' "${PANEL_PATH}/docker-compose.yml"
  fi
  return 0
}

rebecca_uses_compose() {
  [[ -n "$(rebecca_compose_file)" ]] && ! service_registered "$PANEL_SERVICE"
}

rebecca_compose_running() {
  need_cmd docker || return 1
  docker ps --format '{{.Names}}' 2>/dev/null | grep -qi 'rebecca'
}

panel_detect() {
  [[ -d "$PANEL_PATH" ]] && return 0
  service_registered "$PANEL_SERVICE" && return 0
  port_in_use "$PANEL_PORT" && return 0
  return 1
}

panel_version() {
  local version="" cli
  if [[ -r "${PANEL_PATH}/.channel" ]]; then
    version="$(tr -d '[:space:]' <"${PANEL_PATH}/.channel")"
  fi
  if [[ -z "$version" ]]; then
    local compose
    compose="$(rebecca_compose_file)"
    if [[ -n "$compose" ]]; then
      version="$(grep -Em1 'image:.*rebeccapanel/rebecca:' "$compose" 2>/dev/null |
        sed -E 's/.*rebeccapanel\/rebecca:([^"[:space:]]+).*/\1/' || true)"
    fi
  fi
  if [[ -z "$version" ]] && cli="$(rebecca_cli_path)"; then
    version="$("$cli" --version 2>/dev/null | head -n 1 | tr -d '\r' || true)"
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
  if rebecca_uses_compose && rebecca_compose_running; then
    printf '%s\n' running
    return 0
  fi
  printf '%s\n' stopped
}

# --- Version selection ------------------------------------------------------
#
# The official Rebecca installer documents "--dev or --version vX.Y.Z" for both
# install and update, so Rebecca can be pinned to any published release.

panel_available_versions() { panel_versions_available "${1:-5}"; }

panel_version_installer_argv() {
  local version="$1" verb="install"
  # The installer's update verb is the documented way to move an installed
  # Rebecca to another release; install is used when nothing is installed yet.
  if panel_detect; then
    verb="update"
  fi
  if [[ "$version" == "$PANEL_DEV_CHANNEL_KEY" ]]; then
    printf '%s\n' "$verb" --dev
    return 0
  fi
  printf '%s\n' "$verb" --version "$version"
}

panel_install_version() { panel_install_selected_version "$REBECCA_INSTALLER_URL" "${1:-}"; }

panel_install() {
  need_root || return 1
  printf 'Rebecca is installed with its own official installer.\n'
  printf 'Source: %s\n' "$REBECCA_REPO_URL"
  printf 'The installer is downloaded over HTTPS and executed directly; BaToHub does\n'
  printf 'not rewrite it and does not pass it any credentials.\n\n'
  if ! panel_fetch_official_installer "$REBECCA_INSTALLER_URL" install; then
    err "The Rebecca installer did not complete. Full output: ${LOG_FILE}"
    return 1
  fi
  ok "Rebecca installer finished."
}

# BaToHub only manages its own changes. Removing Rebecca itself is left to the
# panel's own uninstaller.
panel_uninstall() {
  need_root || return 1
  printf 'BaToHub does not remove Rebecca. Panel files: %s, data: /var/lib/rebecca\n' "$PANEL_PATH"
  printf 'Use the official Rebecca uninstaller to remove the panel itself.\n\n'
  printf 'BaToHub-managed changes for Rebecca are:\n'
  printf '  subscription template: %s\n' "$(template_target_for "${PANEL_PATH}/.env" "$REBECCA_TEMPLATE_ROOT" "subscription/index.html")"
  printf '  certificates: %s\n' "$PANEL_SSL_DIR"
  if ! ui_confirm_phrase REMOVE 'Remove these BaToHub-managed changes?'; then
    printf 'Nothing was removed.\n'
    return 0
  fi
  panel_template_remove || true
  panel_ssl_remove || true
  ok "BaToHub-managed Rebecca changes were removed. The panel itself is untouched."
}

panel_update() {
  need_root || return 1
  printf 'Updating Rebecca with its official installer.\n'
  if ! panel_fetch_official_installer "$REBECCA_INSTALLER_URL" update; then
    err "The Rebecca updater did not complete. Full output: ${LOG_FILE}"
    return 1
  fi
  ok "Rebecca update finished."
}

panel_logs() {
  if service_registered "$PANEL_SERVICE"; then
    panel_logs_generic "$PANEL_SERVICE" "$PANEL_PATH"
    return 0
  fi
  if rebecca_uses_compose && need_cmd docker; then
    docker compose -f "$(rebecca_compose_file)" -p rebecca logs --tail 80 2>/dev/null ||
      docker logs --tail 80 "$(docker ps -q -f name=rebecca | head -n 1)" 2>/dev/null ||
      warn "Rebecca container logs are not available."
    return 0
  fi
  warn "No log source is available for Rebecca."
  return 1
}

panel_ssl_issue() { panel_submodule ssl && ssl_issue; }
panel_ssl_renew() { panel_submodule ssl && ssl_renew; }
panel_ssl_status() { panel_submodule ssl && ssl_status; }
panel_ssl_remove() { panel_submodule ssl && ssl_remove; }
panel_template_apply() { panel_submodule templates && template_apply; }
panel_template_remove() { panel_submodule templates && template_remove; }
panel_template_status() { panel_submodule templates && template_status; }
panel_menu() { panel_submodule menu && panel_menu_impl; }
