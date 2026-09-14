#!/usr/bin/env bash
set -euo pipefail

. /opt/batohub/lib/common.sh
. /opt/batohub/core/module_loader.sh

. /opt/batohub/panels/rebecca/module.sh
. /opt/batohub/panels/pasarguard/module.sh
. /opt/batohub/panels/3x-ui/module.sh

. /opt/batohub/core/panel_manager.sh
. /opt/batohub/core/ssl_manager.sh
. /opt/batohub/core/template_manager.sh
. /opt/batohub/core/backup_manager.sh

load_panel_list

banner() {
  printf '%s\n' "BaToHub - Central Server Manager"
  printf '%s\n' "Version: $APP_VERSION"
  printf '%s\n' "----------------------------------------"
}

header() {
  clear
  banner
}

pause() {
  read -r -p "Press Enter to continue..." _
}

confirm() {
  local message="$1"
  local answer
  printf '%s\n' "$message"
  read -r -p "Type YES to confirm: " answer
  if [ "${answer:-}" != "YES" ]; then
    info "Action cancelled."
    return 1
  fi
  return 0
}

confirm_destructive() {
  local message="$1"
  local answer
  printf '%s\n' "$message"
  read -r -p "Type REMOVE to confirm: " answer
  if [ "${answer:-}" != "REMOVE" ]; then
    info "Action cancelled."
    return 1
  fi
  return 0
}

panel_selection_menu() {
  while :; do
    header
    printf '%s\n' "Select the panel you want to manage."
    printf '%s\n' "1) Rebecca"
    printf '%s\n' "2) PasarGuard"
    printf '%s\n' "3) 3X-UI (Sanaei)"
    printf '%s\n' "4) Exit"
    read -r -p "Selection: " c
    case "$c" in
      1)
        select_panel "rebecca"
        return
        ;;
      2)
        select_panel "pasarguard"
        return
        ;;
      3)
        select_panel "3x-ui"
        return
        ;;
      4)
        exit 0
        ;;
      *)
        info "Invalid selection."
        pause
        ;;
    esac
  done
}

selected_panel_menu() {
  local panel="$1"
  while :; do
    header
    printf '%s\n' "Panel: $(panel_display_name "$panel")"
    printf '%s\n' "----------------------------------------"
    printf '%s\n' "1) SSL"
    printf '%s\n' "2) Subscription template"
    printf '%s\n' "3) Panel update and status"
    printf '%s\n' "4) Panel logs"
    printf '%s\n' "5) Server info"
    printf '%s\n' "6) BaToHub update"
    printf '%s\n' "7) Settings"
    printf '%s\n' "8) Backup"
    printf '%s\n' "9) Restore"
    printf '%s\n' "10) Import backup"
    printf '%s\n' "11) Uninstall BaToHub"
    printf '%s\n' "0) Exit"
    read -r -p "Selection: " c
    case "$c" in
      1)
        ssl_menu_for_panel "$panel"
        ;;
      2)
        template_menu_for_panel "$panel"
        ;;
      3)
        panel_update_menu "$panel"
        ;;
      4)
        panel_logs_menu "$panel"
        ;;
      5)
        server_menu
        ;;
      6)
        update_all
        ;;
      7)
        settings_menu "$panel"
        ;;
      8)
        backup_menu "$panel"
        ;;
      9)
        restore_menu "$panel"
        ;;
      10)
        import_menu "$panel"
        ;;
      11)
        uninstall_menu
        ;;
      0)
        exit 0
        ;;
      *)
        info "Invalid selection."
        pause
        ;;
    esac
  done
}

server_menu() {
  while :; do
    header
    printf '%s\n' "1) Server information"
    printf '%s\n' "2) Running services"
    printf '%s\n' "3) System resources"
    printf '%s\n' "4) Network"
    printf '%s\n' "5) BaToHub logs"
    printf '%s\n' "0) Back"
    read -r -p "Selection: " c
    case "$c" in
      1)
        header
        printf 'Hostname: '; hostname || true
        if [ -f /etc/os-release ]; then
          . /etc/os-release
          printf 'OS: %s\n' "${PRETTY_NAME:-unknown}"
        else
          printf 'OS: unknown\n'
        fi
        printf 'Kernel: '; uname -r || true
        printf 'Architecture: '; uname -m || true
        pause
        ;;
      2)
        header
        if command -v systemctl >/dev/null 2>&1; then
          systemctl --no-pager --type=service --state=running 2>/dev/null | head -n 35 || true
        else
          err "systemctl is not available."
        fi
        pause
        ;;
      3)
        header
        if command -v free >/dev/null 2>&1; then
          free -h || true
        fi
        echo
        if command -v df >/dev/null 2>&1; then
          df -h / /opt 2>/dev/null || true
        fi
        pause
        ;;
      4)
        header
        if command -v ip >/dev/null 2>&1; then
          ip -brief address 2>/dev/null || true
        fi
        echo
        if command -v ss >/dev/null 2>&1; then
          ss -lntup 2>/dev/null | head -n 40 || true
        fi
        pause
        ;;
      5)
        header
        if [ -f "$LOG_FILE" ]; then
          tail -n 80 "$LOG_FILE"
        else
          err "Log file not found: $LOG_FILE"
        fi
        pause
        ;;
      0) return;;
    esac
  done
}

update_all() {
  . /opt/batohub/core/update.sh
  update_all
}

panel_update_menu() {
  local panel="$1"
  header
  printf '%s\n' "Panel: $(panel_display_name "$panel")"
  printf '%s\n' "----------------------------------------"
  panel_status "$panel"
  pause
  update_panel "$panel"
  pause
}

panel_logs_menu() {
  local panel="$1"
  header
  printf '%s\n' "Panel: $(panel_display_name "$panel")"
  printf '%s\n' "----------------------------------------"
  panel_logs "$panel"
  pause
}

settings_menu() {
  local panel="$1"
  while :; do
    header
    printf '%s\n' "Settings"
    printf '%s\n' "----------------------------------------"
    printf '%s\n' "1) Change selected panel"
    printf '%s\n' "2) Edit panel configuration"
    printf '%s\n' "3) Edit BaToHub configuration"
    printf '%s\n' "0) Back"
    read -r -p "Selection: " c
    case "$c" in
      1)
        header
        if [ -f "${CONFIG_DIR}/panel.conf" ]; then
          info "Current panel configuration:"
          cat "${CONFIG_DIR}/panel.conf"
        fi
        pause
        panel_selection_menu
        return
        ;;
      2)
        header
        if [ -f "${CONFIG_DIR}/panel.conf" ]; then
          editor_yes && vi "${CONFIG_DIR}/panel.conf" || true
        else
          err "Panel configuration not found."
        fi
        pause
        ;;
      3)
        header
        if [ -f "${CONFIG_DIR}/batohub.conf" ]; then
          editor_yes && vi "${CONFIG_DIR}/batohub.conf" || true
        else
          err "BaToHub configuration not found."
        fi
        pause
        ;;
      0) return;;
    esac
  done
}

editor_yes() {
  local answer
  printf '%s\n' "Open editor? This requires an interactive terminal."
  read -r -p "Type YES to open: " answer
  if [ "${answer:-}" != "YES" ]; then
    return 1
  fi
  return 0
}

uninstall_menu() {
  header
  if ! confirm_destructive 'Remove BaToHub from this server?'; then
    pause
    return
  fi
  /opt/batohub/bin/uninstall
}

main() {
  load_panel_list
  local panel
  panel=$(read_panel_config)

  if [ -z "$panel" ] || ! panel_exists "$panel"; then
    panel_selection_menu
    return
  fi

  selected_panel_menu "$panel"
}

main
