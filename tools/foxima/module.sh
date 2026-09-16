#!/usr/bin/env bash
set -Eeuo pipefail

# Foxima tool module.
#
# Foxima (Faoxima) is a PHP management interface that drives several panel
# families. It is distributed as one installer script that deploys a Docker
# Compose stack, installs Docker when it is missing, writes its own
# configuration, and installs a management command on the system. BaToHub
# therefore:
#
#   - never treats Foxima as a panel and never assumes a panel's layout;
#   - never writes the Foxima configuration, because the installer and the
#     installed interface own it;
#   - never removes the stack, its volumes or its data, and only clears the
#     record BaToHub itself wrote;
#   - drives the official installer as supplied by its author.
#
# The project directory is chosen by the installer, so it is detected after the
# installation and recorded rather than being passed in.

FOXIMA_REPO_URL="${FOXIMA_REPO_URL:-https://github.com/Mmd-Amir/Faoxima}"
FOXIMA_INSTALLER_URL="${FOXIMA_INSTALLER_URL:-https://raw.githubusercontent.com/Mmd-Amir/Faoxima/main/install.sh}"

# Values declared by the official installer. They can be overridden for a
# mirrored or relocated installation.
FOXIMA_PROJECT_DIR="${FOXIMA_PROJECT_DIR:-/opt/faoxima}"
FOXIMA_MANAGEMENT_CMD="${FOXIMA_MANAGEMENT_CMD:-/usr/local/bin/faoxima}"
FOXIMA_INSTALLER_LOG="${FOXIMA_INSTALLER_LOG:-/var/log/faoxima_installer.log}"

# The official installer selects its rolling build with -beta.
FOXIMA_CHANNEL_KEY="beta"

foxima_source_repo() {
  local declared
  declared="$(json_get "$TOOL_JSON" source_repo 2>/dev/null || true)"
  printf '%s\n' "${declared:-Mmd-Amir/Faoxima}"
}

foxima_state_file() { printf '%s/tools/foxima/install.path\n' "$STATE_DIR"; }

foxima_recorded_path() {
  local state_file
  state_file="$(foxima_state_file)"
  [[ -r "$state_file" ]] && head -n 1 "$state_file" || true
}

foxima_record_path() {
  local path="$1"
  install -d -m 0750 -o root -g root "$(dirname "$(foxima_state_file)")"
  printf '%s\n' "$path" >"$(foxima_state_file)"
  harden_file "$(foxima_state_file)" 0640
  log "Foxima installation directory recorded: $path"
}

# Prints the project directory of the installation, preferring the recorded
# path and falling back to the directory the installer uses by default.
foxima_installed_path() {
  local recorded fallback
  recorded="$(foxima_recorded_path)"
  if [[ -n "$recorded" && -d "$recorded" ]]; then
    printf '%s\n' "$recorded"
    return 0
  fi
  fallback="$FOXIMA_PROJECT_DIR"
  if [[ -d "$fallback" && (-f "${fallback}/docker-compose.yml" || -f "${fallback}/config.php") ]]; then
    printf '%s\n' "$fallback"
    return 0
  fi
  return 1
}

foxima_compose_file() {
  local dir
  dir="$(foxima_installed_path)" || return 1
  [[ -f "${dir}/docker-compose.yml" ]] || return 1
  printf '%s\n' "${dir}/docker-compose.yml"
}

foxima_config_file() {
  local dir
  dir="$(foxima_installed_path)" || return 1
  printf '%s\n' "${dir}/.env"
}

# Configuration keys of the Foxima configuration file, without their values.
# The values can hold database passwords and bot tokens, so they are never read
# into output.
foxima_config_keys() {
  local file="$1"
  [[ -r "$file" ]] || return 1
  sed -nE 's/^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)=.*/\1/p' "$file" | sort -u
}

foxima_docker_available() {
  need_cmd docker || return 1
  docker compose version >/dev/null 2>&1
}

foxima_stack_running() {
  local compose status
  foxima_docker_available || return 1
  compose="$(foxima_compose_file)" || return 1
  # A Compose project reports the containers that are up; an empty result means
  # the stack exists but nothing is running.
  status="$(docker compose -f "$compose" ps -q 2>/dev/null || true)"
  [[ -n "$status" ]]
}

# The versions a fresh installation can be pinned to: the releases published by
# the project itself, plus the rolling build. An existing installation is
# updated by its own management command, which selects a version itself.
foxima_available_versions() {
  local limit="${1:-5}" tags tag channel count=0
  tags="$(release_tags_for_repo "$(foxima_source_repo)" 30)" || return 1
  while IFS=$'\t' read -r tag channel; do
    [[ -n "$tag" ]] || continue
    [[ "$channel" == "stable" ]] || continue
    printf '%s\n' "$tag"
    count=$((count + 1))
    if [[ "$count" -ge "$limit" ]]; then
      break
    fi
  done <<<"$tags"
  printf '%s\n' "$FOXIMA_CHANNEL_KEY"
  if [[ "$count" -eq 0 ]]; then
    err "No published Foxima release is currently visible."
    return 1
  fi
  return 0
}

foxima_latest_stable_version() {
  local tag channel
  while IFS=$'\t' read -r tag channel; do
    [[ -n "$tag" ]] || continue
    [[ "$channel" == "stable" ]] || continue
    printf '%s\n' "$tag"
    return 0
  done < <(release_tags_for_repo "$(foxima_source_repo)" 30)
  return 1
}

foxima_choose_version() {
  local versions latest default
  versions="$(foxima_available_versions 5)" || return 1
  [[ -n "$versions" ]] || {
    err "No Foxima version could be listed."
    return 1
  }
  latest="$(foxima_latest_stable_version)" || latest=""
  default="${latest:-${versions%%$'\n'*}}"
  choose_version_from_list "$versions" "$default" "$latest"
}

tool_detect() {
  foxima_installed_path >/dev/null && return 0
  [[ -x "$FOXIMA_MANAGEMENT_CMD" ]] && return 0
  return 1
}

tool_version() {
  local path version=""
  if path="$(foxima_installed_path)"; then
    version="$(read_env_value "${path}/.env" FAOXIMA_INSTALLED_VERSION || true)"
    version="$(trim "${version:-}")"
    if [[ -z "$version" && -r "${path}/version" ]]; then
      version="$(tr -d '[:space:]' <"${path}/version")"
    fi
  fi
  printf '%s\n' "${version:-unknown}"
}

tool_status() {
  if ! tool_detect; then
    printf '%s\n' not_installed
    return 0
  fi
  if foxima_stack_running; then
    printf '%s\n' running
    return 0
  fi
  printf '%s\n' stopped
}

# Prints the installer log and the stack log. Both are owned by Foxima; BaToHub
# only reads them.
tool_logs() {
  local compose logs_dir found=0
  if [[ -r "$FOXIMA_INSTALLER_LOG" ]]; then
    printf 'Installer log: %s\n' "$FOXIMA_INSTALLER_LOG"
    tail -n 40 "$FOXIMA_INSTALLER_LOG" || true
    found=1
  fi
  logs_dir="$(foxima_installed_path || true)"
  if [[ -n "$logs_dir" && -d "${logs_dir}/logs" ]]; then
    printf '\nApplication log directory: %s\n' "${logs_dir}/logs"
    find "${logs_dir}/logs" -maxdepth 1 -type f -print0 2>/dev/null |
      sort -z | xargs -0r tail -n 20 || true
    found=1
  fi
  if compose="$(foxima_compose_file)" && foxima_docker_available; then
    printf '\nCompose stack log (last 60 lines):\n'
    if docker compose -f "$compose" logs --tail 60 2>/dev/null; then
      found=1
    fi
  fi
  if [[ "$found" -eq 0 ]]; then
    warn "No log source is available for Foxima."
    return 1
  fi
  return 0
}

# Shows where the configuration lives and which settings it holds. Payment
# gateway settings, panel connections and general settings belong to Foxima and
# are changed in its own interface; BaToHub does not write this file.
tool_configure() {
  local dir file key
  ui_title "Foxima configuration"
  dir="$(foxima_installed_path || true)"
  if [[ -z "$dir" ]]; then
    printf 'Foxima is not installed on this server.\n'
    printf 'Install it first: the official installer creates its configuration.\n'
    return 1
  fi
  file="${dir}/.env"
  printf 'Project directory: %s\n' "$dir"
  printf 'Configuration file: %s\n' "$file"
  printf 'Management command: %s\n' "$FOXIMA_MANAGEMENT_CMD"
  printf 'Installer log: %s\n\n' "$FOXIMA_INSTALLER_LOG"
  printf 'Payment gateways, panel connections and general settings are owned by\n'
  printf 'Foxima. Change them in the Foxima interface, or with the management\n'
  printf 'command above. BaToHub does not write this file.\n\n'
  if [[ ! -r "$file" ]]; then
    warn "The configuration file could not be read: $file"
    return 1
  fi
  printf 'Settings defined in this file (values are not printed):\n'
  while IFS= read -r key; do
    [[ -n "$key" ]] || continue
    case "$key" in
    *PAY* | *GATE* | *CARD* | *BANK* | *ZARIN* | *WALLET* | *PRICE* | *PLAN*) printf '  payment:  %s\n' "$key" ;;
    *PANEL* | *MARZBAN* | *X_UI* | *XUI* | *REBECCA* | *PASARGUARD*) printf '  panel:    %s\n' "$key" ;;
    *) printf '  setting:  %s\n' "$key" ;;
    esac
  done < <(foxima_config_keys "$file")
  return 0
}

# Removes the record BaToHub wrote and nothing else. The stack, its volumes, its
# configuration and its data belong to the operator and are left untouched.
tool_uninstall() {
  need_root || return 1
  local state_file
  state_file="$(foxima_state_file)"
  printf 'BaToHub does not remove Foxima. The stack, its Docker volumes, its\n'
  printf 'configuration and its data stay in place.\n\n'
  printf 'Foxima-managed files that BaToHub never touches:\n'
  printf '  project directory: %s\n' "$(foxima_installed_path || printf '%s' "$FOXIMA_PROJECT_DIR")"
  printf '  management command: %s\n' "$FOXIMA_MANAGEMENT_CMD"
  printf '  installer log: %s\n\n' "$FOXIMA_INSTALLER_LOG"
  printf 'BaToHub-managed state for Foxima:\n'
  if [[ -r "$state_file" ]]; then
    printf '  recorded installation path: %s\n' "$state_file"
  else
    printf '  none\n'
  fi
  if [[ ! -r "$state_file" ]]; then
    printf '\nThere is nothing for BaToHub to remove.\n'
    printf 'To remove the installation itself, use the Foxima management command.\n'
    return 0
  fi
  if ! ui_confirm_phrase REMOVE 'Clear the BaToHub record for Foxima?'; then
    printf 'Nothing was removed.\n'
    return 0
  fi
  rm -f -- "$state_file"
  ok "The BaToHub record for Foxima was cleared. Foxima itself was not touched."
  printf 'BaToHub no longer remembers the project directory; it is detected again\n'
  printf 'from the default location the next time it is needed.\n'
  return 0
}

# Optional interface function: the versions a fresh installation can be pinned
# to. A tool whose installer resolves the newest release itself does not
# implement it, and the command reports that instead of inventing a list.
tool_available_versions() { foxima_available_versions "${1:-5}"; }

# Optional interface function: install one chosen version. The version is
# validated before any other step, so an unexpected value changes nothing.
tool_install_version() { tool_submodule install && foxima_install_version "${1:-}"; }

tool_install() { tool_submodule install && tool_install_impl; }
tool_update() { tool_submodule install && tool_update_impl; }
tool_menu() { tool_submodule menu && tool_menu_impl; }
