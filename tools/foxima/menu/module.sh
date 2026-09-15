#!/usr/bin/env bash
set -Eeuo pipefail

# Foxima tool menu.

tool_menu_impl() {
  local choice path
  while true; do
    ui_title "Foxima"
    printf '1) Status\n'
    printf '2) Install\n'
    printf '3) Update\n'
    printf '4) Remove a BaToHub-recorded installation\n'
    printf '0) Back\n'
    choice="$(ui_menu_choice)"
    case "$choice" in
    1)
      ui_title "Foxima status"
      printf 'State: %s\n' "$(panel_status_text "$(tool_status)")"
      printf 'Version: %s\n' "$(tool_version)"
      path="$(foxima_recorded_path)"
      printf 'Recorded path: %s\n' "${path:-none}"
      if foxima_web_server_active; then
        printf 'Web server: active\n'
      else
        printf 'Web server: not active\n'
      fi
      pause
      ;;
    2)
      tool_install
      pause
      ;;
    3)
      tool_update_impl
      pause
      ;;
    4)
      tool_uninstall
      pause
      ;;
    0) return 0 ;;
    *) warn 'Invalid selection.' ;;
    esac
  done
}
