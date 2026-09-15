#!/usr/bin/env bash
set -Eeuo pipefail

# 3X-UI panel module.
#
# 3X-UI is installed by its own installer under /usr/local/x-ui and keeps its
# configuration and database in /etc/x-ui. The panel CLI name is x-ui, while the
# systemd service is also called x-ui.

XUI_INSTALLER_URL="${XUI_INSTALLER_URL:-https://raw.githubusercontent.com/MHSanaei/3x-ui/master/install.sh}"
XUI_REPO_URL="${XUI_REPO_URL:-https://github.com/MHSanaei/3x-ui}"

xui_cli_path() {
  local candidate
  for candidate in "$PANEL_CLI" "/usr/local/x-ui/x-ui" "/usr/bin/x-ui" "/usr/local/bin/x-ui"; do
    if [[ -n "$candidate" && -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

xui_cli_supports() {
  # Runtime capability probe: an option is only used when the installed CLI
  # reports it, so BaToHub never claims a feature the panel does not have.
  local cli="$1" flag="$2"
  "$cli" setting --help 2>&1 | grep -q -- "$flag"
}

panel_detect() {
  [[ -d "$PANEL_PATH" ]] && return 0
  service_registered "$PANEL_SERVICE" && return 0
  port_in_use "$PANEL_PORT" && return 0
  return 1
}

panel_version() {
  local version="" cli
  if cli="$(xui_cli_path)"; then
    version="$("$cli" version 2>/dev/null | head -n 1 | tr -d '\r' || true)"
    if [[ -z "$version" ]]; then
      version="$("$cli" --version 2>/dev/null | head -n 1 | tr -d '\r' || true)"
    fi
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
  printf '3X-UI is installed with its official installer.\n'
  printf 'Source: %s\n\n' "$XUI_REPO_URL"
  if ! panel_fetch_official_installer "$XUI_INSTALLER_URL" ""; then
    err "The 3X-UI installer did not complete. Full output: ${LOG_FILE}"
    return 1
  fi
  ok "3X-UI installer finished."
}

panel_uninstall() {
  need_root || return 1
  printf 'BaToHub does not remove 3X-UI. Panel files: %s, database: /etc/x-ui/x-ui.db\n' "$PANEL_PATH"
  printf 'Use the official 3X-UI uninstaller to remove the panel itself.\n\n'
  printf 'BaToHub-managed changes for 3X-UI are:\n'
  printf '  staged templates: %s\n' "$PANEL_TEMPLATE_DIR"
  printf '  certificates: %s\n' "$PANEL_SSL_DIR"
  if ! ui_confirm_phrase REMOVE 'Remove these BaToHub-managed changes?'; then
    printf 'Nothing was removed.\n'
    return 0
  fi
  panel_template_remove || true
  panel_ssl_remove || true
  ok "BaToHub-managed 3X-UI changes were removed. The panel itself and its database are untouched."
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
