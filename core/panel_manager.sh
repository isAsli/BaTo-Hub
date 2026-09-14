#!/usr/bin/env bash
set -euo pipefail

. /opt/batohub/lib/common.sh

PANEL_CONF="${CONFIG_DIR}/panel.conf"

read_panel_config() {
  if [ ! -f "$PANEL_CONF" ]; then
    printf ''
    return 0
  fi
  local panel
  panel=$(grep -E '^PANEL=' "$PANEL_CONF" 2>/dev/null | sed 's/^PANEL=//' | tr -d '[:space:]' | head -n 1 || true)
  printf '%s' "${panel:-}"
}

write_panel_config() {
  local panel="$1"
  local port="$2"
  local path="$3"
  local domain="$4"
  local installed_at
  installed_at="$(date '+%F %T')"

  install -d "$CONFIG_DIR" 2>/dev/null || true
  chmod 750 "$CONFIG_DIR" 2>/dev/null || true
  chown root:root "$CONFIG_DIR" 2>/dev/null || true

  local content
  content=$(printf '%s\n' \
    "PANEL=${panel}" \
    "PANEL_PORT=${port}" \
    "PANEL_PATH=${path}" \
    "PANEL_DOMAIN=${domain}" \
    "INSTALLED_AT=${installed_at}")
  write_protected_file "$PANEL_CONF" "$content"
  chmod 600 "$PANEL_CONF" 2>/dev/null || true
  chown root:root "$PANEL_CONF" 2>/dev/null || true
}

select_panel() {
  local panel="$1"
  local port path domain installed_at
  port=$(panel_default_port "$panel")
  path=$(panel_default_path "$panel")
  domain=""
  installed_at="$(date '+%F %T')"

  if panel_detect "$panel"; then
    domain=$(panel_configured_domain "$panel")
  fi

  write_panel_config "$panel" "$port" "$path" "$domain" "$installed_at"
  ok "Panel selected: $(panel_display_name "$panel")"
  pause
  exec_panel_menu "$panel"
}

exec_panel_menu() {
  local panel="$1"
  . /opt/batohub/core/main.sh
  selected_panel_menu "$panel"
}

panel_default_port() {
  local name="$1"
  local json
  if json=$(panel_json_path "$name"); then
    printf '%s' "$(json_get "$json" "default_port")"
  else
    printf '80'
  fi
}

panel_default_path() {
  local name="$1"
  local json
  if json=$(panel_json_path "$name"); then
    printf '%s' "$(json_get "$json" "default_path")"
  else
    printf '/opt/${panel}'
  fi
}

panel_configured_domain() {
  local name="$1"
  local panel_dir
  panel_dir=$(panel_detect_path "$name")
  if [ -z "$panel_dir" ]; then
    printf ''
    return 0
  fi
  local env_file="${panel_dir}/.env"
  if [ -f "$env_file" ]; then
    grep -E '^DOMAIN=' "$env_file" 2>/dev/null | sed 's/^DOMAIN=//' | tr -d '[:space:]' | head -n 1 || true
  fi
  printf ''
}

panel_status_text() {
  local panel="$1"
  panel_status "$panel" | sed -n '1p'
}
