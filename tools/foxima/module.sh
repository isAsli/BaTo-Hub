#!/usr/bin/env bash
set -Eeuo pipefail

# Foxima tool module.
#
# Foxima is a PHP interface that is normally installed on a web hosting stack
# such as cPanel or aaPanel. BaToHub does not reimplement the installer and does
# not modify a hosting control panel: it checks the prerequisites, runs the
# official installer where the operator asks for it, and records the path it
# used so a later removal stays inside BaToHub-managed files.

FOXIMA_REPO_URL="${FOXIMA_REPO_URL:-https://github.com/Mmd-Amir/Faoxima}"
FOXIMA_INSTALLER_URL="${FOXIMA_INSTALLER_URL:-https://raw.githubusercontent.com/Mmd-Amir/Faoxima/main/install.sh}"

foxima_paths() {
  printf '%s\n' "${FOXIMA_PATH:-/var/www/foxima}"
  printf '%s\n' "/opt/foxima"
  printf '%s\n' "/var/www/html/foxima"
}

foxima_state_file() { printf '%s/tools/foxima/install.path\n' "$STATE_DIR"; }

foxima_recorded_path() {
  local state_file
  state_file="$(foxima_state_file)"
  [[ -r "$state_file" ]] && head -n 1 "$state_file" || true
}

foxima_installed_path() {
  local recorded path
  recorded="$(foxima_recorded_path)"
  if [[ -n "$recorded" && -d "$recorded" ]]; then
    printf '%s\n' "$recorded"
    return 0
  fi
  while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    if [[ -d "$path" ]]; then
      printf '%s\n' "$path"
      return 0
    fi
  done < <(foxima_paths)
  return 1
}

foxima_web_server_active() {
  local service
  for service in nginx apache2 httpd lsws; do
    if service_active "$service"; then
      return 0
    fi
  done
  return 1
}

tool_detect() {
  foxima_installed_path >/dev/null
}

tool_version() {
  local path version_file
  if path="$(foxima_installed_path)"; then
    for version_file in "${path}/VERSION" "${path}/version.txt"; do
      if [[ -r "$version_file" ]]; then
        head -n 1 "$version_file" | tr -d '[:space:]'
        return 0
      fi
    done
  fi
  printf '%s\n' unknown
}

tool_status() {
  if ! tool_detect; then
    printf '%s\n' not_installed
    return 0
  fi
  if foxima_web_server_active; then
    printf '%s\n' running
    return 0
  fi
  printf '%s\n' stopped
}

tool_install() { tool_submodule install && tool_install_impl; }
tool_uninstall() { tool_submodule install && tool_uninstall_impl; }
tool_menu() { tool_submodule menu && tool_menu_impl; }
