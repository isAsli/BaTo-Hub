#!/usr/bin/env bash
set -Eeuo pipefail

# PasarGuard panel module.
#
# PasarGuard is installed by its own script and exposes a service, a .env file
# and a data directory. All of them are declared in panel.json.

PASARGUARD_SCRIPT_URL="${PASARGUARD_SCRIPT_URL:-https://raw.githubusercontent.com/PasarGuard/scripts/main/pasarguard.sh}"
PASARGUARD_REPO_URL="${PASARGUARD_REPO_URL:-https://github.com/PasarGuard/panel}"
PASARGUARD_TEMPLATE_ROOT="${PASARGUARD_TEMPLATE_ROOT:-/var/lib/pasarguard/templates}"

pasarguard_cli_path() {
  local candidate
  for candidate in "/usr/local/bin/pasarguard" "${PANEL_PATH}/pasarguard" "${PANEL_CLI}"; do
    if [[ -n "$candidate" && -x "$candidate" ]]; then
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
  local version="" cli
  if [[ -r "${PANEL_PATH}/.env" ]]; then
    version="$(read_env_value "${PANEL_PATH}/.env" APP_VERSION || true)"
  fi
  if [[ -z "$version" ]] && cli="$(pasarguard_cli_path)"; then
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
  printf '%s\n' stopped
}

panel_install() {
  need_root || return 1
  printf 'PasarGuard is installed with its official installer script.\n'
  printf 'Source: %s\n\n' "$PASARGUARD_REPO_URL"
  if ! panel_fetch_official_installer "$PASARGUARD_SCRIPT_URL" install; then
    err "The PasarGuard installer did not complete. Full output: ${LOG_FILE}"
    return 1
  fi
  ok "PasarGuard installer finished."
}

panel_uninstall() {
  need_root || return 1
  printf 'BaToHub does not remove PasarGuard. Panel files: %s, data: /var/lib/pasarguard\n' "$PANEL_PATH"
  printf 'Use the official PasarGuard script to remove the panel itself.\n\n'
  printf 'BaToHub-managed changes for PasarGuard are:\n'
  printf '  subscription template: %s\n' "$(template_target_for "${PANEL_PATH}/.env" "$PASARGUARD_TEMPLATE_ROOT" "subscription/index.html")"
  printf '  certificates: %s\n' "$PANEL_SSL_DIR"
  if ! ui_confirm_phrase REMOVE 'Remove these BaToHub-managed changes?'; then
    printf 'Nothing was removed.\n'
    return 0
  fi
  panel_template_remove || true
  panel_ssl_remove || true
  ok "BaToHub-managed PasarGuard changes were removed. The panel itself is untouched."
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
