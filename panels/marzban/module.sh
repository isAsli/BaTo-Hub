#!/usr/bin/env bash
set -Eeuo pipefail

# Marzban panel module.
#
# Marzban is a Python and React panel. Its service, configuration and data
# locations are declared in panel.json and read back through the loader.

MARZBAN_SCRIPT_URL="${MARZBAN_SCRIPT_URL:-https://raw.githubusercontent.com/Gozargah/Marzban-scripts/master/marzban.sh}"
MARZBAN_REPO_URL="${MARZBAN_REPO_URL:-https://github.com/Gozargah/Marzban}"
MARZBAN_TEMPLATE_ROOT="${MARZBAN_TEMPLATE_ROOT:-/var/lib/marzban/templates}"

marzban_cli_path() {
  local candidate
  for candidate in "/usr/local/bin/marzban" "/usr/local/bin/marzban-cli" "${PANEL_PATH}/marzban-cli"; do
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
  if [[ -z "$version" ]] && cli="$(marzban_cli_path)"; then
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
  printf 'Marzban is installed with its official installer script.\n'
  printf 'Source: %s\n\n' "$MARZBAN_REPO_URL"
  if ! panel_fetch_official_installer "$MARZBAN_SCRIPT_URL" install; then
    err "The Marzban installer did not complete. Full output: ${LOG_FILE}"
    return 1
  fi
  ok "Marzban installer finished."
}

panel_uninstall() {
  need_root || return 1
  printf 'BaToHub does not remove Marzban. Panel files: %s, data: /var/lib/marzban\n' "$PANEL_PATH"
  printf 'Use the official Marzban script to remove the panel itself.\n\n'
  printf 'BaToHub-managed changes for Marzban are:\n'
  printf '  subscription template: %s\n' "$(template_target_for "${PANEL_PATH}/.env" "$MARZBAN_TEMPLATE_ROOT" "subscription/index.html")"
  printf '  certificates: %s\n' "$PANEL_SSL_DIR"
  if ! ui_confirm_phrase REMOVE 'Remove these BaToHub-managed changes?'; then
    printf 'Nothing was removed.\n'
    return 0
  fi
  panel_template_remove || true
  panel_ssl_remove || true
  ok "BaToHub-managed Marzban changes were removed. The panel itself is untouched."
}

panel_update() {
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
  ok "Marzban update finished."
  return 0
}

panel_logs() { panel_logs_generic "$PANEL_SERVICE" "$PANEL_PATH"; }

panel_ssl_issue() { panel_submodule ssl && ssl_issue; }
panel_ssl_renew() { panel_submodule ssl && ssl_renew; }
panel_ssl_status() { panel_submodule ssl && ssl_status; }
panel_ssl_remove() { panel_submodule ssl && ssl_remove; }
panel_template_apply() { panel_submodule templates && template_apply; }
panel_template_remove() { panel_submodule templates && template_remove; }
panel_template_status() { panel_submodule templates && template_status; }
panel_menu() { panel_submodule menu && panel_menu_impl; }
