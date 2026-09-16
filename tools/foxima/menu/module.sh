#!/usr/bin/env bash
set -Eeuo pipefail

# Foxima tool menu.
#
# Every entry reports what it did. The removal entry clears the record BaToHub
# wrote and states plainly that the installation, its configuration, its volumes
# and its data are not touched.

# Reports where the installation is and which commands belong to it.
foxima_menu_detect() {
  local config
  ui_title "Foxima installation"
  if ! tool_detect; then
    printf 'State: not installed\n'
    printf 'Checked the recorded path, %s, and %s\n' "$FOXIMA_PROJECT_DIR" "$FOXIMA_MANAGEMENT_CMD"
    return 0
  fi
  printf 'State: installed\n'
  printf 'Project directory: %s\n' "$(foxima_installed_path)"
  printf 'Version: %s\n' "$(tool_version)"
  config="$(foxima_config_file || true)"
  printf 'Configuration file: %s\n' "${config:-not found}"
  printf 'Management command: %s (%s)\n' "$FOXIMA_MANAGEMENT_CMD" \
    "$([[ -x "$FOXIMA_MANAGEMENT_CMD" ]] && printf 'present' || printf 'not present')"
  printf 'Installer log: %s\n' "$FOXIMA_INSTALLER_LOG"
  return 0
}

foxima_menu_status() {
  ui_title "Foxima status"
  printf 'State: %s\n' "$(panel_status_text "$(tool_status)")"
  printf 'Version: %s\n' "$(tool_version)"
  printf 'Project directory: %s\n' "$(foxima_installed_path || printf 'not found')"
  printf 'Recorded by BaToHub: %s\n' "$(foxima_recorded_path || printf 'no')"
  printf 'Docker: %s\n' "$(foxima_docker_available && printf 'available' || printf 'not available')"
  printf 'Compose stack: %s\n' "$(foxima_stack_running && printf 'running' || printf 'not running')"
  return 0
}

foxima_menu_logs() {
  ui_title "Foxima logs"
  tool_logs
}

# The support handle is documentation only and is never written into source
# files, so it is read from the shipped documentation at run time.
foxima_support_handle() {
  local doc handle
  for doc in \
    "${BATOHUB_ROOT:-/opt/batohub}/README.md" \
    "${BATOHUB_ROOT:-/opt/batohub}/DOCS.md"; do
    [[ -r "$doc" ]] || continue
    handle="$(grep -oE '@[A-Za-z_][A-Za-z0-9_]{2,}' "$doc" 2>/dev/null | tail -n 1 || true)"
    if [[ -n "$handle" ]]; then
      printf '%s\n' "$handle"
      return 0
    fi
  done
  return 1
}

foxima_menu_support() {
  local handle
  ui_title "Foxima support"
  printf 'Foxima is a separate project with its own maintainers.\n'
  printf 'Repository: %s\n\n' "$FOXIMA_REPO_URL"
  printf 'For Foxima itself, including the installation, the interface and the\n'
  printf 'billing features, use the channels published by that project.\n\n'
  printf 'For BaToHub, including this integration:\n'
  if handle="$(foxima_support_handle)"; then
    printf '  Support contact: %s\n' "$handle"
  else
    printf '  See the Contact section of the BaToHub documentation.\n'
  fi
  return 0
}

tool_menu_impl() {
  local choice state
  while true; do
    state="$(tool_status)"
    ui_title "Foxima (${state})"
    printf '1) Detect the installation\n'
    printf '2) Install Foxima\n'
    printf '3) Update Foxima\n'
    printf '4) Status\n'
    printf '5) Logs\n'
    printf '6) Configure (payment gateways, panels, settings)\n'
    printf '7) Clear the BaToHub record for Foxima\n'
    printf '8) Support contact\n'
    printf '0) Back\n'
    choice="$(ui_menu_choice)"
    case "$choice" in
    1)
      foxima_menu_detect
      pause
      ;;
    2)
      tool_install
      pause
      ;;
    3)
      tool_update
      pause
      ;;
    4)
      foxima_menu_status
      pause
      ;;
    5)
      foxima_menu_logs
      pause
      ;;
    6)
      tool_configure
      pause
      ;;
    7)
      tool_uninstall
      pause
      ;;
    8)
      foxima_menu_support
      pause
      ;;
    0) return 0 ;;
    *) warn 'Invalid selection.' ;;
    esac
  done
}
