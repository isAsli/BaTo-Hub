#!/usr/bin/env bash
set -Eeuo pipefail

# BaToHub entry point.
#
# This file is executed by bin/batohub. It exposes the interactive interface and
# a non-interactive command interface used by automation and by the release
# checks. Every user facing message is plain text; no ANSI art, no emoji.

if [[ -z "${BATOHUB_ROOT:-}" ]]; then
  self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  BATOHUB_ROOT="$(cd "${self_dir}/.." && pwd)"
  export BATOHUB_ROOT
fi

# shellcheck source=/dev/null
. "${BATOHUB_ROOT}/lib/common.sh"
# shellcheck source=/dev/null
. "${BATOHUB_ROOT}/lib/panel_helpers.sh"
# shellcheck source=/dev/null
. "${BATOHUB_ROOT}/lib/ssl_helpers.sh"
# shellcheck source=/dev/null
. "${BATOHUB_ROOT}/lib/template_helpers.sh"
# shellcheck source=/dev/null
. "${BATOHUB_ROOT}/lib/backup_helpers.sh"
# shellcheck source=/dev/null
. "${BATOHUB_ROOT}/core/panel_loader.sh"
# shellcheck source=/dev/null
. "${BATOHUB_ROOT}/core/backup_manager.sh"
# shellcheck source=/dev/null
. "${BATOHUB_ROOT}/core/tools_manager.sh"
# shellcheck source=/dev/null
. "${BATOHUB_ROOT}/core/update.sh"
# shellcheck source=/dev/null
. "${BATOHUB_ROOT}/security/integrity.sh"

usage() {
  cat <<'EOF'
BaToHub - central server manager for proxy and VPN panels

Usage:
  BaToHub                      Open the interactive interface
  BaToHub --menu               Open the interactive interface
  BaToHub --help               Show this help
  BaToHub --version            Print the BaToHub version
  BaToHub --list-panels        List supported panels
  BaToHub --detect             List panels detected on this server
  BaToHub --status             Print a status summary
  BaToHub --select-panel NAME  Configure the panel BaToHub manages
  BaToHub --panel NAME CMD     Run one panel command without the menu
  BaToHub --tools              List supported tools
  BaToHub --backup             Create a backup now
  BaToHub --restore FILE       Restore a backup archive
  BaToHub --update             Update BaToHub from the configured source
  BaToHub --check              Verify the integrity manifest
  BaToHub --rebuild-integrity  Rebuild the integrity manifest and verify it
  BaToHub --validate           Validate every panel and tool interface
  BaToHub --uninstall          Remove BaToHub (keeps panels and their data)

Panel commands for --panel: detect, version, status, install, uninstall,
ssl-issue, ssl-renew, ssl-status, template-apply, template-status,
template-remove, update, logs.
EOF
}

panel_list_lines() {
  local name state version
  while IFS= read -r name; do
    [[ -n "$name" ]] || continue
    state="$(panel_state_of "$name")"
    version="$(panel_version_of "$name")"
    printf '  %-10s %-14s %-14s %s\n' "$name" "$(panel_display_for "$name")" \
      "$(panel_status_text "$state")" "version ${version:-unknown}"
  done < <(loader_panels)
}

tool_list_lines() {
  local name
  while IFS= read -r name; do
    [[ -n "$name" ]] || continue
    printf '  %-10s %s\n' "$name" "$(json_get "${TOOL_DIR}/${name}/tool.json" display_name)"
  done < <(loader_tools)
}

status_summary() {
  local panel state version
  panel="$(panel_config_name)"
  printf 'BaToHub version: %s\n' "$APP_VERSION"
  printf 'Install path: %s\n' "$INSTALL_DIR"
  printf 'Operating system: %s\n' "$(os_pretty_name)"
  printf 'Architecture: %s\n' "$(uname -m)"
  printf 'Integrity: '
  if integrity_check_quiet; then
    printf 'verified\n'
  elif [[ -f "$INTEGRITY_MANIFEST" ]]; then
    printf 'mismatched files detected\n'
  else
    printf 'manifest missing\n'
  fi
  if [[ -z "$panel" ]]; then
    printf 'Panel: not configured\n'
    return 0
  fi
  if ! panel_exists "$panel"; then
    printf 'Panel: %s (not available in this release)\n' "$panel"
    return 0
  fi
  state="$(panel_state_of "$panel")"
  version="$(panel_version_of "$panel")"
  printf 'Panel: %s\n' "$(panel_display_for "$panel")"
  printf 'Panel state: %s\n' "$(panel_status_text "$state")"
  printf 'Panel version: %s\n' "${version:-unknown}"
  printf 'Panel service: %s\n' "$(panel_service_for "$panel")"
  printf 'Panel SSL directory: %s\n' "$(panel_ssl_dir_for "$panel")"
  return 0
}

configure_panel() {
  local name="$1" domain=""
  panel_exists "$name" || {
    err "Unsupported panel: $name"
    return 1
  }
  if panel_detect_state "$name"; then
    domain="$(panel_configured_domain "$name")"
  fi
  panel_config_write "$name" "$domain" || return 1
  ok "Panel configured: $(panel_display_for "$name")"
  return 0
}

panel_configured_domain() {
  local name="$1" env_file domain=""
  env_file="$(panel_env_file_for "$name")"
  if [[ -n "$env_file" && -r "$env_file" ]]; then
    domain="$(read_env_value "$env_file" DOMAIN || true)"
  fi
  printf '%s\n' "$domain"
}

panel_env_file_for() {
  local name="$1" path
  path="$(panel_path_for "$name")"
  if [[ -r "${path}/.env" ]]; then
    printf '%s\n' "${path}/.env"
  fi
}

# Interactive first run. The panel that BaToHub manages is detected when
# possible, and the detected result is always confirmed by the operator before
# it is stored.
first_run_flow() {
  local detected=() name
  while IFS= read -r name; do
    [[ -n "$name" ]] && detected+=("$name")
  done < <(panels_detected)

  case "${#detected[@]}" in
  1)
    name="${detected[0]}"
    ui_title "Detected panel"
    printf 'Your panel appears to be %s.\n' "$(panel_display_for "$name")"
    if ui_confirm 'Is that correct?'; then
      configure_panel "$name" || return 1
      selected_panel_menu "$name"
      return 0
    fi
    panel_choice_menu
    return 0
    ;;
  0)
    ui_title "No panel found"
    printf 'BaToHub could not find a panel compatible with it on this server.\n'
    printf 'Supported panels:\n'
    panel_list_lines
    printf '\n'
    if ui_confirm 'Do you want to install one?'; then
      panel_install_menu
      return 0
    fi
    printf '\nIf your panel is not among the supported panels, it is not compatible with BaToHub.\n'
    printf 'Requests for additional panels are handled through the support contact listed in the README.\n'
    limited_menu
    return 0
    ;;
  *)
    ui_title "Multiple panels detected"
    printf 'More than one supported panel is installed. Choose the one BaToHub should manage.\n\n'
    panel_choice_menu
    return 0
    ;;
  esac
}

panel_choice_menu() {
  local choice index=0 name names=()
  while IFS= read -r name; do
    [[ -n "$name" ]] && names+=("$name")
  done < <(loader_panels)
  ui_title "Panel selection"
  for name in "${names[@]}"; do
    index=$((index + 1))
    printf '%s) %s\n' "$index" "$(panel_display_for "$name")"
  done
  printf '0) Exit\n'
  choice="$(ui_menu_choice)"
  [[ "$choice" =~ ^[0-9]+$ ]] || {
    warn "Invalid selection."
    return 1
  }
  if [[ "$choice" == 0 ]]; then
    return 0
  fi
  name="${names[$((choice - 1))]:-}"
  [[ -n "$name" ]] || {
    warn "Invalid selection."
    return 1
  }
  configure_panel "$name" || return 1
  selected_panel_menu "$name"
}

panel_install_menu() {
  local choice name names=() index=0
  while IFS= read -r name; do
    [[ -n "$name" ]] && names+=("$name")
  done < <(loader_panels)
  ui_title "Install a panel"
  for name in "${names[@]}"; do
    index=$((index + 1))
    printf '%s) %s\n' "$index" "$(panel_display_for "$name")"
  done
  printf '0) Back\n'
  choice="$(ui_menu_choice)"
  [[ "$choice" =~ ^[0-9]+$ ]] || {
    warn "Invalid selection."
    return 1
  }
  [[ "$choice" == 0 ]] && return 0
  name="${names[$((choice - 1))]:-}"
  [[ -n "$name" ]] || {
    warn "Invalid selection."
    return 1
  }
  panel_load "$name" || return 1
  panel_install || return 1
  configure_panel "$name" || return 1
  selected_panel_menu "$name"
}

# The reduced menu is shown when no supported panel is installed and the
# operator does not want to install one right now.
limited_menu() {
  local choice
  while true; do
    ui_title "Limited menu (no panel configured)"
    printf '1) Install a new panel\n'
    printf '2) Tools\n'
    printf '3) Settings\n'
    printf '4) Update BaToHub\n'
    printf '5) Integrity check\n'
    printf '0) Exit\n'
    choice="$(ui_menu_choice)"
    case "$choice" in
    1) panel_install_menu ;;
    2) tools_menu ;;
    3) settings_menu ;;
    4) update_menu ;;
    5) integrity_menu ;;
    0) return 0 ;;
    *) warn 'Invalid selection.' ;;
    esac
  done
}

selected_panel_menu() {
  local panel="$1" choice state
  if [[ "$INTERACTIVE" != 1 ]]; then
    err "The interactive interface requires a terminal. Use --status or --help instead."
    return 1
  fi
  if ! loader_load_panel "$panel"; then
    err "Panel could not be loaded: $panel"
    return 1
  fi
  while true; do
    state="$(panel_status)"
    ui_title "Panel: ${PANEL_DISPLAY} (${state})"
    printf '1) SSL management\n'
    printf '2) Subscription template\n'
    printf '3) Panel status\n'
    printf '4) Panel update\n'
    printf '5) Panel logs\n'
    printf '6) Server information\n'
    printf '7) Tools\n'
    printf '8) Backup\n'
    printf '9) Restore\n'
    printf '10) Import backup\n'
    printf '11) Settings\n'
    printf '12) Update BaToHub\n'
    printf '13) Integrity check\n'
    printf '14) Uninstall BaToHub\n'
    printf '0) Exit\n'
    choice="$(ui_menu_choice)"
    case "$choice" in
    1) ssl_menu ;;
    2) template_menu ;;
    3) panel_status_menu ;;
    4) panel_update_menu ;;
    5) panel_logs_menu ;;
    6) server_menu ;;
    7) tools_menu ;;
    8) backup_menu ;;
    9) restore_menu ;;
    10) import_menu "$PANEL_NAME" ;;
    11) settings_menu ;;
    12) update_menu ;;
    13) integrity_menu ;;
    14) uninstall_menu ;;
    0) return 0 ;;
    *) warn 'Invalid selection.' ;;
    esac
  done
}

ssl_menu() {
  local choice
  while true; do
    ui_title "SSL - ${PANEL_DISPLAY}"
    printf '1) Issue a certificate\n'
    printf '2) Renew certificates\n'
    printf '3) Certificate status\n'
    printf '4) Remove BaToHub-managed certificate files\n'
    printf '0) Back\n'
    choice="$(ui_menu_choice)"
    case "$choice" in
    1) panel_ssl_issue ;;
    2) panel_ssl_renew ;;
    3) panel_ssl_status ;;
    4) panel_ssl_remove ;;
    0) return 0 ;;
    *) warn 'Invalid selection.' ;;
    esac
    pause
  done
}

template_menu() {
  local choice
  while true; do
    ui_title "Subscription template - ${PANEL_DISPLAY}"
    printf '1) Apply the BaToHub template\n'
    printf '2) Template status\n'
    printf '3) Remove the BaToHub template\n'
    printf '0) Back\n'
    choice="$(ui_menu_choice)"
    case "$choice" in
    1) panel_template_apply ;;
    2) panel_template_status ;;
    3) panel_template_remove ;;
    0) return 0 ;;
    *) warn 'Invalid selection.' ;;
    esac
    pause
  done
}

panel_status_menu() {
  local state version
  state="$(panel_status)"
  version="$(panel_version)"
  ui_title "Panel status - ${PANEL_DISPLAY}"
  printf 'State: %s\n' "$(panel_status_text "$state")"
  printf 'Version: %s\n' "${version:-unknown}"
  printf 'Service: %s\n' "$PANEL_SERVICE"
  printf 'Install path: %s\n' "$PANEL_PATH"
  printf 'Default port: %s\n' "$PANEL_PORT"
  if service_registered "$PANEL_SERVICE"; then
    systemctl status "$PANEL_SERVICE" --no-pager -n 10 2>/dev/null || true
  else
    printf 'systemd unit: not registered\n'
  fi
  pause
}

panel_update_menu() {
  ui_title "Panel update - ${PANEL_DISPLAY}"
  panel_update
  pause
}

panel_logs_menu() {
  ui_title "Panel logs - ${PANEL_DISPLAY}"
  panel_logs
  pause
}

server_menu() {
  local choice
  while true; do
    ui_title "Server information"
    printf '1) Summary\n'
    printf '2) Resources\n'
    printf '3) Network interfaces and listeners\n'
    printf '4) Running services\n'
    printf '5) BaToHub log\n'
    printf '0) Back\n'
    choice="$(ui_menu_choice)"
    case "$choice" in
    1)
      ui_title "Server summary"
      printf 'Hostname: %s\n' "$(hostname 2>/dev/null || printf unknown)"
      printf 'Operating system: %s\n' "$(os_pretty_name)"
      printf 'Kernel: %s\n' "$(uname -r)"
      printf 'Architecture: %s\n' "$(uname -m)"
      printf 'Uptime: %s\n' "$(uptime -p 2>/dev/null || printf unknown)"
      printf 'Public address: %s\n' "$(server_public_ip)"
      pause
      ;;
    2)
      ui_title "Resources"
      free -h 2>/dev/null || true
      printf '\n'
      df -h / /opt 2>/dev/null || df -h / 2>/dev/null || true
      pause
      ;;
    3)
      ui_title "Network"
      ip -brief address 2>/dev/null || true
      printf '\n'
      ss -lntup 2>/dev/null | head -n 40 || true
      pause
      ;;
    4)
      ui_title "Running services"
      if systemd_available; then
        systemctl --no-pager --type=service --state=running 2>/dev/null | head -n 40 || true
      else
        warn "systemd is not available on this system."
      fi
      pause
      ;;
    5)
      ui_title "BaToHub log"
      show_logs
      pause
      ;;
    0) return 0 ;;
    *) warn 'Invalid selection.' ;;
    esac
  done
}

settings_menu() {
  local choice panel
  panel="$(panel_config_name)"
  while true; do
    ui_title "Settings"
    printf 'Current panel: %s\n\n' "${panel:-not configured}"
    printf '1) Change the managed panel\n'
    printf '2) Edit the panel configuration\n'
    printf '3) Edit the BaToHub configuration\n'
    printf '4) Show the BaToHub configuration\n'
    printf '0) Back\n'
    choice="$(ui_menu_choice)"
    case "$choice" in
    1)
      printf 'Switching the managed panel does not modify or remove the previous panel.\n'
      if ui_confirm 'Continue?'; then
        panel_choice_menu
        panel="$(panel_config_name)"
      fi
      ;;
    2)
      if [[ -f "$PANEL_CONF" ]]; then
        edit_file "$PANEL_CONF"
      else
        warn "Panel configuration does not exist yet: $PANEL_CONF"
      fi
      pause
      ;;
    3)
      if [[ -f "$CONFIG_FILE" ]]; then
        edit_file "$CONFIG_FILE"
      else
        warn "BaToHub configuration is missing: $CONFIG_FILE"
      fi
      pause
      ;;
    4)
      ui_title "BaToHub configuration"
      if [[ -r "$CONFIG_FILE" ]]; then
        grep -vE '^[[:space:]]*(#|$)' "$CONFIG_FILE" || true
      else
        warn "BaToHub configuration is missing: $CONFIG_FILE"
      fi
      pause
      ;;
    0) return 0 ;;
    *) warn 'Invalid selection.' ;;
    esac
  done
}

edit_file() {
  local target="$1" editor
  editor="${EDITOR:-vi}"
  if [[ "$INTERACTIVE" != 1 ]]; then
    warn "An interactive terminal is required to edit files."
    return 1
  fi
  need_cmd "$editor" || {
    warn "Editor not found: $editor"
    return 1
  }
  "$editor" "$target"
  log "Edited file: $target"
}

integrity_menu() {
  local choice
  while true; do
    ui_title "Integrity"
    printf 'Manifest: %s\n\n' "$INTEGRITY_MANIFEST"
    printf '1) Run the integrity check\n'
    printf '2) Rebuild the manifest and verify it\n'
    printf '3) Validate every panel and tool interface\n'
    printf '0) Back\n'
    choice="$(ui_menu_choice)"
    case "$choice" in
    1)
      if integrity_check; then
        ok "All managed files match the manifest."
      fi
      pause
      ;;
    2)
      if integrity_rebuild_and_verify; then
        :
      fi
      pause
      ;;
    3)
      loader_validate_all || true
      pause
      ;;
    0) return 0 ;;
    *) warn 'Invalid selection.' ;;
    esac
  done
}

update_menu() {
  ui_title "Update BaToHub"
  update_all
  pause
}

uninstall_menu() {
  ui_title "Uninstall BaToHub"
  printf 'This removes BaToHub files and state. Panels, their data and their\n'
  printf 'certificates are not removed.\n\n'
  if ! ui_confirm_phrase REMOVE 'Remove BaToHub from this server?'; then
    return 0
  fi
  "${INSTALL_DIR}/bin/uninstall" || return 1
  return 0
}

interactive_main() {
  local panel
  need_root || return 1
  ensure_runtime_dirs || true
  integrity_apply_before_run || true
  panel="$(panel_config_name)"
  if [[ -n "$panel" ]]; then
    if panel_exists "$panel"; then
      selected_panel_menu "$panel"
      return 0
    fi
    err "The configured panel is not available in this release: $panel"
    printf 'Choose a supported panel to continue.\n'
  fi
  first_run_flow
}

cli_panel_command() {
  local name="${1:-}" command="${2:-}"
  [[ -n "$name" && -n "$command" ]] || {
    err "Usage: BaToHub --panel <panel> <command>"
    return 2
  }
  loader_load_panel "$name" || return 1
  case "$command" in
  detect) panel_detect ;;
  version) panel_version ;;
  status) panel_status ;;
  install)
    need_root || return 1
    panel_install
    ;;
  uninstall)
    need_root || return 1
    panel_uninstall
    ;;
  ssl-issue)
    need_root || return 1
    panel_ssl_issue
    ;;
  ssl-renew)
    need_root || return 1
    panel_ssl_renew
    ;;
  ssl-status) panel_ssl_status ;;
  template-apply)
    need_root || return 1
    panel_template_apply
    ;;
  template-status) panel_template_status ;;
  template-remove)
    need_root || return 1
    panel_template_remove
    ;;
  update)
    need_root || return 1
    panel_update
    ;;
  logs) panel_logs ;;
  *)
    err "Unknown panel command: $command"
    return 2
    ;;
  esac
}

main() {
  case "${1:-}" in
  "" | --menu | -m)
    interactive_main
    ;;
  -h | --help)
    usage
    ;;
  -V | --version)
    printf 'BaToHub %s\n' "$APP_VERSION"
    ;;
  --list-panels)
    printf 'Supported panels:\n'
    panel_list_lines
    ;;
  --tools)
    printf 'Supported tools:\n'
    tool_list_lines
    ;;
  --detect)
    local name found=0
    while IFS= read -r name; do
      [[ -n "$name" ]] || continue
      found=1
      printf '%s\n' "$name"
    done < <(panels_detected)
    [[ "$found" -eq 1 ]] || printf 'No supported panel was detected.\n'
    ;;
  --status)
    status_summary
    ;;
  --select-panel)
    need_root || return 1
    configure_panel "${2:?panel name is required}" || return 1
    ;;
  --panel)
    shift
    cli_panel_command "$@"
    ;;
  --backup)
    need_root || return 1
    backup_create "$(panel_config_name)"
    ;;
  --restore)
    need_root || return 1
    backup_restore "${2:?backup archive is required}" "$(panel_config_name)"
    ;;
  --update)
    need_root || return 1
    update_all
    ;;
  --check)
    integrity_check
    ;;
  --rebuild-integrity)
    need_root || return 1
    integrity_rebuild_and_verify
    ;;
  --validate)
    loader_validate_all
    ;;
  --uninstall)
    need_root || return 1
    "${INSTALL_DIR}/bin/uninstall"
    ;;
  *)
    err "Unknown option: $1"
    usage
    return 2
    ;;
  esac
}

main "$@"
