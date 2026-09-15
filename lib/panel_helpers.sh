#!/usr/bin/env bash
set -Eeuo pipefail

# Panel context helpers.
#
# The loader fills PANEL_NAME, PANEL_DISPLAY, PANEL_JSON, PANEL_DIR, PANEL_PATH,
# PANEL_SERVICE, PANEL_PORT, PANEL_CLI, PANEL_SSL_DIR and PANEL_TEMPLATE_DIR
# before a panel module is sourced. Panel modules only rely on the panel.json
# values plus the generic helpers below, so no module ever hard-codes another
# module's paths.

panel_meta_get() {
  local name="$1" field="$2" metadata
  metadata="${PANEL_DIR}/${name}/panel.json"
  [[ -r "$metadata" ]] || return 1
  json_get "$metadata" "$field"
}

panel_meta_list() {
  local name="$1" field="$2" metadata
  metadata="${PANEL_DIR}/${name}/panel.json"
  [[ -r "$metadata" ]] || return 1
  json_list "$metadata" "$field"
}

panel_exists() {
  [[ -r "${PANEL_DIR}/${1}/panel.json" && -r "${PANEL_DIR}/${1}/module.sh" ]]
}

panel_path_for() { panel_meta_get "$1" default_path; }
panel_service_for() { panel_meta_get "$1" service_name; }
panel_port_for() { panel_meta_get "$1" default_port; }
panel_display_for() { panel_meta_get "$1" display_name; }
panel_cli_for() { panel_meta_get "$1" cli_name; }
panel_supports_bare_ip() { [[ "$(panel_meta_get "$1" supports_bare_ip_ssl)" == "true" ]]; }

panel_storage_dir() { printf '%s/panels/%s\n' "$STATE_DIR" "$1"; }
panel_ssl_dir_for() { printf '%s/panels/%s/ssl\n' "$STATE_DIR" "$1"; }
panel_template_dir_for() { printf '%s/panels/%s/templates\n' "$STATE_DIR" "$1"; }

# Populates the documented panel context for one panel.
panel_context_load() {
  local name="$1"
  panel_exists "$name" || {
    err "Panel is not installed in this BaToHub release: $name"
    return 1
  }
  # These variables are the contract that panel modules rely on.
  export PANEL_NAME="$name"
  export PANEL_DISPLAY PANEL_JSON PANEL_MODULE_DIR PANEL_PATH PANEL_SERVICE
  PANEL_DISPLAY="$(panel_display_for "$name")"
  PANEL_JSON="${PANEL_DIR}/${name}/panel.json"
  PANEL_MODULE_DIR="${PANEL_DIR}/${name}"
  PANEL_PATH="$(panel_path_for "$name")"
  PANEL_SERVICE="$(panel_service_for "$name")"
  PANEL_PORT="$(panel_port_for "$name")"
  PANEL_CLI="$(panel_cli_for "$name")"
  export PANEL_PORT PANEL_CLI PANEL_SSL_DIR PANEL_TEMPLATE_DIR PANEL_SUBMODULES SSL_TARGET
  PANEL_SSL_DIR="$(panel_ssl_dir_for "$name")"
  PANEL_TEMPLATE_DIR="$(panel_template_dir_for "$name")"
  PANEL_SUBMODULES=""
  SSL_TARGET=""
}

# Panel modules are sourced one at a time; the previously loaded interface is
# dropped first so that two panels can never share function definitions.
panel_context_unload() {
  local fn
  for fn in panel_detect panel_version panel_status panel_install panel_uninstall \
    panel_ssl_issue panel_ssl_renew panel_template_apply panel_template_remove \
    panel_update panel_logs panel_menu; do
    unset -f "$fn" 2>/dev/null || true
  done
  PANEL_NAME=""
  PANEL_MODULE_DIR=""
  PANEL_SUBMODULES=""
}

panel_load() {
  local name="$1" module
  [[ "${PANEL_NAME:-}" == "$name" ]] && return 0
  panel_context_unload
  panel_context_load "$name" || return 1
  module="${PANEL_MODULE_DIR}/module.sh"
  # shellcheck source=/dev/null
  source "$module"
}

# Sources a panel sub-module exactly once per loaded panel.
panel_submodule() {
  local sub="$1" file
  [[ -n "${PANEL_MODULE_DIR:-}" ]] || {
    err "No panel is loaded."
    return 1
  }
  file="${PANEL_MODULE_DIR}/${sub}/module.sh"
  [[ -r "$file" ]] || {
    err "Panel ${PANEL_NAME} has no ${sub} module in this release."
    return 1
  }
  case " ${PANEL_SUBMODULES:-} " in
  *" ${sub} "*) return 0 ;;
  esac
  # shellcheck source=/dev/null
  source "$file"
  PANEL_SUBMODULES="${PANEL_SUBMODULES:-} ${sub}"
}

# Detection is always evaluated in a subshell so a failed panel load cannot
# terminate the caller.
panel_detect_state() {
  local name="$1"
  (panel_load "$name" && panel_detect) >/dev/null 2>&1
}

panel_state_of() {
  local name="$1"
  (panel_load "$name" && panel_status) 2>/dev/null | tail -n 1
}

panel_version_of() {
  local name="$1"
  (panel_load "$name" && panel_version) 2>/dev/null | tail -n 1
}

panels_all() {
  local metadata
  shopt -s nullglob
  for metadata in "${PANEL_DIR}"/*/panel.json; do
    basename "$(dirname "$metadata")"
  done
  shopt -u nullglob
}

panels_detected() {
  local name
  while IFS= read -r name; do
    [[ -n "$name" ]] || continue
    panel_detect_state "$name" && printf '%s\n' "$name"
  done < <(panels_all)
}

# Paths that BaToHub may read or write for a panel. Used by backup and update.
panel_declared_paths() {
  local name="$1" path
  while IFS= read -r path; do
    [[ -n "$path" ]] && printf '%s\n' "$path"
  done < <(panel_meta_list "$name" config_paths)
  while IFS= read -r path; do
    [[ -n "$path" ]] && printf '%s\n' "$path"
  done < <(panel_meta_list "$name" data_paths)
  printf '%s\n' "$(panel_ssl_dir_for "$name")"
  printf '%s\n' "$(panel_template_dir_for "$name")"
}

panel_restart_safe() {
  local service="${1:-$PANEL_SERVICE}"
  if service_registered "$service"; then
    if ! run_logged "restart ${service}" systemctl restart "$service"; then
      err "Service ${service} failed to restart. Inspect: journalctl -u ${service} -n 50"
      return 1
    fi
    ok "Service ${service} restarted."
    return 0
  fi
  warn "Service ${service} is not registered with systemd; configuration was written but nothing was restarted."
  return 0
}

panel_detect_generic() {
  [[ -n "${PANEL_PATH:-}" && -d "$PANEL_PATH" ]] && return 0
  [[ -n "${PANEL_CLI:-}" && -x "$PANEL_CLI" ]] && return 0
  service_registered "${PANEL_SERVICE:-}" && return 0
  port_in_use "${PANEL_PORT:-}" && return 0
  return 1
}

panel_version_generic() {
  local version=""
  if [[ -n "${PANEL_CLI:-}" && -x "$PANEL_CLI" ]]; then
    version="$("$PANEL_CLI" --version 2>/dev/null | head -n 1 | tr -d '\r' || true)"
  fi
  if [[ -z "$version" && -n "${PANEL_PATH:-}" && -r "${PANEL_PATH}/VERSION" ]]; then
    version="$(head -n 1 "${PANEL_PATH}/VERSION" | tr -d '[:space:]')"
  fi
  if [[ -z "$version" && -r "${PANEL_PATH:-/nonexistent}/.env" ]]; then
    version="$(read_env_value "${PANEL_PATH}/.env" APP_VERSION || true)"
  fi
  printf '%s\n' "${version:-unknown}"
}

panel_status_generic() {
  if ! panel_detect_generic; then
    printf '%s\n' not_installed
  elif service_active "${PANEL_SERVICE:-}"; then
    printf '%s\n' running
  else
    printf '%s\n' stopped
  fi
}

panel_status_text() {
  local state
  state="${1:-not_installed}"
  case "$state" in
  running) printf '%s\n' 'running' ;;
  stopped) printf '%s\n' 'stopped' ;;
  *) printf '%s\n' 'not installed' ;;
  esac
}

panel_logs_generic() {
  local service="${1:-$PANEL_SERVICE}" path="${2:-$PANEL_PATH}"
  if service_registered "$service"; then
    journalctl -u "$service" -n 80 --no-pager
    return 0
  fi
  if [[ -d "$path/logs" ]]; then
    find "$path/logs" -maxdepth 1 -type f -print0 | sort -z | xargs -0r tail -n 40
    return 0
  fi
  warn "No log source is available for ${service}."
  return 1
}

panel_env_set() {
  local env_file="$1" key="$2" value="$3"
  [[ -f "$env_file" ]] || {
    err "Panel configuration file is missing: $env_file"
    return 1
  }
  with_lock panel-env set_env_value "$env_file" "$key" "$value" || {
    err "Failed to update ${key} in ${env_file}"
    return 1
  }
}

panel_env_apply() {
  # Applies "KEY=VALUE" pairs read on stdin. Values are never passed on the
  # command line, so they cannot leak through the process list.
  local env_file="$1" line key value
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    key="${line%%=*}"
    value="${line#*=}"
    panel_env_set "$env_file" "$key" "$value" || return 1
  done
}

panel_fetch_official_installer() {
  local url="$1" action="$2" log_target="${3:-$LOG_FILE}" tmp
  [[ "$url" == https://* ]] || {
    err "Refusing to download an installer over a non-HTTPS URL: $url"
    return 1
  }
  need_cmd curl || {
    err "curl is required to download the installer."
    return 1
  }
  tmp="$(mktemp_file installer)"
  # shellcheck disable=SC2064
  trap "rm -f -- '$tmp'" RETURN
  if ! curl --fail --location --show-error --silent --retry 3 --proto '=https' \
    --tlsv1.2 --output "$tmp" "$url"; then
    err "Download failed: $url"
    return 1
  fi
  [[ -s "$tmp" ]] || {
    err "Downloaded installer is empty: $url"
    return 1
  }
  if [[ -n "$action" ]]; then
    bash "$tmp" "$action" >>"$log_target" 2>&1
  else
    bash "$tmp" >>"$log_target" 2>&1
  fi
}

# Persists the selected panel. The file is created with mode 0600 because it is
# BaToHub state, and it is written through the shared lock so two runs cannot
# interleave.
panel_config_write() {
  local name="$1" domain="${2:-}" port path content
  panel_exists "$name" || {
    err "Unsupported panel: $name"
    return 1
  }
  port="$(panel_port_for "$name")"
  path="$(panel_path_for "$name")"
  content="$(printf 'PANEL=%s\nPANEL_PORT=%s\nPANEL_PATH=%s\nPANEL_DOMAIN=%s\nINSTALLED_AT=%s\n' \
    "$name" "$port" "$path" "$domain" "$(date '+%F %T')")"
  install -d -m 0750 -o root -g root "$CONFIG_DIR"
  with_lock panel-config atomic_write "$PANEL_CONF" 0600 "$content" || {
    err "Failed to write $PANEL_CONF"
    return 1
  }
  harden_dir "$CONFIG_DIR" 0750
  harden_file "$PANEL_CONF" 0600
  log "Panel configuration written: $name"
  return 0
}

panel_config_name() {
  local name
  name="$(state_read PANEL || true)"
  printf '%s\n' "$(trim "${name:-}")"
}

panel_meta_summary() {
  local name="$1"
  printf 'Panel: %s\n' "$(panel_display_for "$name")"
  printf 'Install path: %s\n' "$(panel_path_for "$name")"
  printf 'Service: %s\n' "$(panel_service_for "$name")"
  printf 'Default port: %s\n' "$(panel_port_for "$name")"
  printf 'CLI: %s\n' "$(panel_cli_for "$name")"
}
