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

# Downloads an official installer over HTTPS into a temporary file and prints
# its path. The caller runs it and removes it.
panel_download_official_installer() {
  local url="$1" tmp
  [[ "$url" == https://* ]] || {
    err "Refusing to download an installer over a non-HTTPS URL: $url"
    return 1
  }
  need_cmd curl || {
    err "curl is required to download the installer."
    return 1
  }
  tmp="$(mktemp_file installer)"
  if ! curl --fail --location --show-error --silent --retry 3 \
    --proto '=https' --proto-redir '=https' \
    --tlsv1.2 --output "$tmp" "$url"; then
    rm -f -- "$tmp"
    err "Download failed: $url"
    return 1
  fi
  if [[ ! -s "$tmp" ]]; then
    rm -f -- "$tmp"
    err "Downloaded installer is empty: $url"
    return 1
  fi
  printf '%s\n' "$tmp"
}

# Runs a downloaded installer with the given arguments. Arguments are passed as
# a list, so no argument is ever interpreted by a shell.
panel_fetch_official_installer_args() {
  local url="$1" log_target="${LOG_FILE}" status=0 tmp
  shift
  tmp="$(panel_download_official_installer "$url")" || return 1
  set +e
  bash "$tmp" "$@" >>"$log_target" 2>&1
  status=$?
  set -e
  rm -f -- "$tmp"
  if [[ "$status" -ne 0 ]]; then
    return "$status"
  fi
  return 0
}

panel_fetch_official_installer() {
  local url="$1" action="$2" log_target="${3:-$LOG_FILE}"
  if [[ -n "$action" ]]; then
    panel_fetch_official_installer_args "$url" "$action"
  else
    panel_fetch_official_installer_args "$url"
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

# ---------------------------------------------------------------------------
# Panel version detection and selection.
#
# Version pinning runs through each panel's own installer: the panel module
# declares the argument its installer expects for a version, and the helpers
# here resolve the published versions from the panel's own repository, present
# the choice, run the installer, read the installed version back and record the
# change under ${LOG_DIR}. No version list is maintained in BaToHub, so a new
# release of a panel is selectable without changing this project.
# ---------------------------------------------------------------------------

# Selects a panel's development or preview channel instead of a release tag.
PANEL_DEV_CHANNEL_KEY="dev"

# A version is handed to an installer as one argument, so it is validated
# before it is used.
PANEL_VERSION_PATTERN='^[A-Za-z0-9][A-Za-z0-9._+-]*$'

panel_valid_version_string() {
  local version="$1"
  [[ -n "$version" ]] || {
    err "A version is required."
    return 1
  }
  if [[ ${#version} -gt 64 || ! "$version" =~ $PANEL_VERSION_PATTERN ]]; then
    err "Refusing an unexpected version string: ${version}"
    return 1
  fi
  return 0
}

panel_source_repo() { panel_meta_get "$1" source_repo; }
panel_version_pin_scope() { panel_meta_get "$1" version_pin_scope; }
panel_dev_channel_argument() { panel_meta_get "$1" dev_channel_argument; }

panel_supports_version_pinning() {
  [[ "$(panel_meta_get "$1" supports_version_pinning)" == "true" ]]
}

# Published release tags of a repository, newest first, as "tag<TAB>channel"
# where channel is stable or prerelease. Only the published release list of that
# repository is read; no version list is maintained in BaToHub.
release_tags_for_repo() {
  local repo="$1" limit="${2:-20}" url log_target="/dev/null"
  [[ -n "$repo" ]] || {
    err "No source repository is declared for this panel."
    return 1
  }
  need_cmd curl || {
    err "curl is required to list the published versions."
    return 1
  }
  need_cmd python3 || {
    err "python3 is required to list the published versions."
    return 1
  }
  # The transport errors of the request are recorded in the log when it exists,
  # and discarded otherwise, so a missing log file cannot fail the listing.
  if [[ -n "${LOG_FILE:-}" ]]; then
    ensure_runtime_dirs >/dev/null 2>&1 || true
    [[ -e "$LOG_FILE" ]] && log_target="$LOG_FILE"
  fi
  url="https://api.github.com/repos/${repo}/releases?per_page=${limit}"
  curl --fail --silent --show-error --retry 3 --location \
    --proto '=https' --proto-redir '=https' \
    --tlsv1.2 --header 'Accept: application/vnd.github+json' "$url" \
    2>>"$log_target" |
    python3 -c '
import json
import sys

try:
    releases = json.load(sys.stdin)
except ValueError:
    raise SystemExit(1)
if not isinstance(releases, list):
    raise SystemExit(1)
for release in releases:
    tag = release.get("tag_name") or ""
    if not tag or release.get("draft"):
        continue
    channel = "prerelease" if release.get("prerelease") else "stable"
    sys.stdout.write(tag + "\t" + channel + "\n")
'
}

# The stable releases a panel offers, newest first, limited to the number asked
# for. The development channel is offered as the key "dev" when the panel
# declares one. A panel module adds further channels by appending them to this
# output.
panel_versions_available() {
  local limit="${1:-5}" name="${PANEL_NAME:-}" tags tag channel dev_arg count=0
  tags="$(release_tags_for_repo "$(panel_source_repo "$name")" 30)" || return 1
  while IFS=$'\t' read -r tag channel; do
    [[ -n "$tag" ]] || continue
    [[ "$channel" == "stable" ]] || continue
    printf '%s\n' "$tag"
    count=$((count + 1))
    if [[ "$count" -ge "$limit" ]]; then
      break
    fi
  done <<<"$tags"
  dev_arg="$(panel_dev_channel_argument "$name")"
  if [[ -n "$dev_arg" ]]; then
    printf '%s\n' "$PANEL_DEV_CHANNEL_KEY"
  fi
  if [[ "$count" -eq 0 && -z "$dev_arg" ]]; then
    return 1
  fi
  return 0
}

# The newest published stable release of the loaded panel.
panel_latest_stable_version() {
  local tag channel
  while IFS=$'\t' read -r tag channel; do
    [[ -n "$tag" ]] || continue
    [[ "$channel" == "stable" ]] || continue
    printf '%s\n' "$tag"
    return 0
  done < <(release_tags_for_repo "$(panel_source_repo "${PANEL_NAME:-}")" 30)
  return 1
}

# Prints numbered choices for a version list. The newest stable release is
# marked and the development channel is labelled.
version_choices_lines() {
  local versions="$1" latest="$2" key index=0
  while IFS= read -r key; do
    [[ -n "$key" ]] || continue
    index=$((index + 1))
    if [[ "$key" == "$PANEL_DEV_CHANNEL_KEY" ]]; then
      printf '%s) %s (development channel)\n' "$index" "$key"
    elif [[ -n "$latest" && "$key" == "$latest" ]]; then
      printf '%s) %s (latest stable)\n' "$index" "$key"
    else
      printf '%s) %s\n' "$index" "$key"
    fi
  done <<<"$versions"
}

# Prompts for a choice from a version list, prints the chosen key, and accepts a
# version typed in instead of a number. Used by the panel menu and by tools.
choose_version_from_list() {
  local versions="$1" default="$2" latest="${3:-}" key answer index=0
  [[ -n "$versions" ]] || {
    err "No version could be listed."
    return 1
  }
  [[ -n "$default" ]] || default="${versions%%$'\n'*}"
  version_choices_lines "$versions" "$latest"
  printf '0) Back\n'
  answer="$(trim "$(ui_prompt "Select a version [${default}]: " '')")"
  if [[ -z "$answer" ]]; then
    printf '%s\n' "$default"
    return 0
  fi
  if [[ "$answer" == "0" ]]; then
    return 1
  fi
  if [[ "$answer" =~ ^[0-9]+$ ]]; then
    while IFS= read -r key; do
      [[ -n "$key" ]] || continue
      index=$((index + 1))
      if [[ "$index" -eq "$answer" ]]; then
        printf '%s\n' "$key"
        return 0
      fi
    done <<<"$versions"
    err "Selection is out of range: ${answer}"
    return 1
  fi
  panel_valid_version_string "$answer" || return 1
  printf '%s\n' "$answer"
}

# Prompts for a panel version and prints the chosen key. The default is the
# newest published stable release.
panel_choose_version() {
  local versions latest default
  versions="$(panel_available_versions 5)" || return 1
  [[ -n "$versions" ]] || {
    err "No version of ${PANEL_DISPLAY:-$PANEL_NAME} could be listed."
    return 1
  }
  latest="$(panel_latest_stable_version)" || latest=""
  default="${latest:-${versions%%$'\n'*}}"
  choose_version_from_list "$versions" "$default" "$latest"
}

# Records a version change of a panel or a tool with a timestamp, both in the
# main log file and in ${LOG_DIR}/versions.log. Only versions and outcomes are
# recorded, never configuration values.
version_change_log() {
  local component="$1" action="$2" before="$3" after="$4" requested="$5"
  install -d -m 0750 -o root -g root "$LOG_DIR" 2>/dev/null || true
  printf '[%s] component=%s action=%s requested=%s before=%s after=%s\n' \
    "$(date '+%F %T%z')" "$component" "$action" "${requested:-none}" \
    "${before:-unknown}" "${after:-unknown}" >>"${LOG_DIR}/versions.log" 2>/dev/null || true
  log "VERSION component=${component} action=${action} requested=${requested:-none} before=${before:-unknown} after=${after:-unknown}"
}

# Reads the version back and compares it with the requested one. A panel
# reports its own version string, which can differ in form from the release tag,
# so a difference is reported instead of being treated as a confirmed install.
panel_version_verify() {
  local requested="$1" actual="$2" want have
  if [[ -z "$actual" || "$actual" == "unknown" ]]; then
    warn "The installed version could not be read back from ${PANEL_DISPLAY:-$PANEL_NAME}."
    return 0
  fi
  if [[ "$requested" == "$PANEL_DEV_CHANNEL_KEY" ]]; then
    printf 'Installed version: %s (development channel)\n' "$actual"
    return 0
  fi
  want="${requested#v}"
  have="${actual#v}"
  if [[ "$want" == "$have" || "$actual" == *"$want"* ]]; then
    ok "Installed version confirmed: ${actual}"
    return 0
  fi
  warn "The panel reports version ${actual} while ${requested} was requested."
  warn "Review the installer output in ${LOG_FILE}"
  return 0
}

# Reported when a panel's official installer cannot be pinned to a version.
panel_version_pinning_unsupported() {
  local version="${1:-}"
  err "${PANEL_DISPLAY:-$PANEL_NAME} does not support version pinning."
  err "Its official installer always installs the newest published release."
  if [[ -n "$version" ]]; then
    err "Version ${version} cannot be selected. Use the panel install or update action instead."
  fi
  return 1
}

# Installs one version through the panel installer and records the change. Used
# by the version menu and by --panel NAME install-version.
panel_version_install_selected() {
  local version="${1:-}" before after
  # The version is validated before anything else, so an unexpected value is
  # refused without touching the system.
  panel_valid_version_string "$version" || return 1
  need_root || return 1
  before="$(panel_version)"
  printf 'Panel: %s\n' "${PANEL_DISPLAY:-$PANEL_NAME}"
  printf 'Installed version: %s\n' "$before"
  printf 'Version requested: %s\n\n' "$version"
  if ! panel_install_version "$version"; then
    err "${PANEL_DISPLAY:-$PANEL_NAME} was not installed from version ${version}."
    version_change_log "$PANEL_NAME" install "$before" "$(panel_version)" "$version"
    return 1
  fi
  after="$(panel_version)"
  printf 'Installed version after the operation: %s\n' "$after"
  version_change_log "$PANEL_NAME" install "$before" "$after" "$version"
  panel_version_verify "$version" "$after"
  ok "${PANEL_DISPLAY:-$PANEL_NAME} version selection finished."
  return 0
}

# The interactive version entry: prompts for a version, then installs it.
panel_version_install_flow() {
  local version
  need_root || return 1
  ui_title "Panel version - ${PANEL_DISPLAY}"
  printf 'Installed version: %s\n\n' "$(panel_version)"
  version="$(panel_choose_version)" || return 1
  panel_version_install_selected "$version"
}

# Prints the published versions of the loaded panel.
panel_version_list() {
  local versions latest
  printf 'Published versions of %s (source: %s)\n\n' \
    "${PANEL_DISPLAY:-$PANEL_NAME}" "$(panel_source_repo "$PANEL_NAME")"
  versions="$(panel_available_versions 5)" || return 1
  [[ -n "$versions" ]] || {
    err "No version of ${PANEL_DISPLAY:-$PANEL_NAME} could be listed."
    return 1
  }
  latest="$(panel_latest_stable_version)" || latest=""
  version_choices_lines "$versions" "$latest"
  if ! panel_supports_version_pinning "$PANEL_NAME"; then
    printf '\nThe official installer of %s always installs the newest release.\n' \
      "${PANEL_DISPLAY:-$PANEL_NAME}"
    printf 'BaToHub does not reimplement it, so only the newest release can be installed.\n'
  fi
  return 0
}

# The version entry of the panel menu.
panel_version_menu() {
  local choice
  ui_title "Panel version - ${PANEL_DISPLAY}"
  printf 'Installed version: %s\n' "$(panel_version)"
  if panel_supports_version_pinning "$PANEL_NAME"; then
    printf 'Version pinning: supported (%s)\n\n' "$(panel_version_pin_scope "$PANEL_NAME")"
  else
    printf 'Version pinning: not supported by the official installer\n\n'
  fi
  printf '1) Install or switch to a chosen version\n'
  printf '2) List the published versions\n'
  printf '0) Back\n'
  choice="$(ui_menu_choice)"
  case "$choice" in
  1) panel_version_install_flow ;;
  2) panel_version_list ;;
  *) return 0 ;;
  esac
}

# The update entry of the panel menu. When the panel can be pinned, the operator
# chooses between the newest release and a specific version.
panel_version_update_menu() {
  local choice
  if ! panel_supports_version_pinning "$PANEL_NAME"; then
    panel_update
    return $?
  fi
  ui_title "Panel update - ${PANEL_DISPLAY}"
  printf 'Installed version: %s\n\n' "$(panel_version)"
  printf '1) Update to the newest published release\n'
  printf '2) Install or switch to a chosen version\n'
  printf '0) Back\n'
  choice="$(ui_menu_choice)"
  case "$choice" in
  1) panel_update ;;
  2) panel_version_install_flow ;;
  *) return 0 ;;
  esac
}

# Runs the panel's installer with the argv the panel declares for a version.
# The installer is downloaded over HTTPS and executed as supplied by its
# author; BaToHub does not rewrite it and passes no credentials to it.
panel_install_selected_version() {
  local url="$1" version="${2:-}" argv=() line
  panel_valid_version_string "$version" || return 1
  need_root || return 1
  while IFS= read -r line; do
    argv+=("$line")
  done < <(panel_version_installer_argv "$version")
  if [[ "${#argv[@]}" -eq 0 ]]; then
    err "${PANEL_DISPLAY:-$PANEL_NAME} declares no installer argument for version ${version}."
    return 1
  fi
  printf 'Running the official installer of %s for version %s\n' \
    "${PANEL_DISPLAY:-$PANEL_NAME}" "$version"
  if ! panel_fetch_official_installer_args "$url" "${argv[@]}"; then
    err "The ${PANEL_DISPLAY:-$PANEL_NAME} installer did not complete. Full output: ${LOG_FILE}"
    return 1
  fi
  ok "The ${PANEL_DISPLAY:-$PANEL_NAME} installer finished for version ${version}."
  return 0
}
