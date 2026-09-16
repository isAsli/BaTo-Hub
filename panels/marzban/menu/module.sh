#!/usr/bin/env bash
set -Eeuo pipefail

# Marzban panel menu.

panel_menu_impl() {
  local choice state
  while true; do
    state="$(panel_status)"
    ui_title "Marzban (${state})"
    printf '1) SSL management\n'
    printf '2) Subscription template\n'
    printf '3) Panel status\n'
    printf '4) Panel update\n'
    printf '5) Panel logs\n'
    printf '6) Remove BaToHub-managed Marzban changes\n'
    printf '0) Back\n'
    choice="$(ui_menu_choice)"
    case "$choice" in
    1)
      printf '1) Issue  2) Renew  3) Status  4) Remove\n'
      case "$(ui_menu_choice)" in
      1) panel_ssl_issue ;;
      2) panel_ssl_renew ;;
      3) panel_ssl_status ;;
      4) panel_ssl_remove ;;
      esac
      pause
      ;;
    2)
      printf '1) Apply  2) Status  3) Remove\n'
      case "$(ui_menu_choice)" in
      1) panel_template_apply ;;
      2) panel_template_status ;;
      3) panel_template_remove ;;
      esac
      pause
      ;;
    3)
      panel_status_menu
      ;;
    4)
      panel_version_update_menu
      pause
      ;;
    5)
      panel_logs
      pause
      ;;
    6)
      panel_uninstall
      pause
      ;;
    0) return 0 ;;
    *) warn 'Invalid selection.' ;;
    esac
  done
}
